require 'lib_enums'
class Account < ApplicationRecord
  attr_accessor :search_date_begin, :search_date_end

  ENUMS = %w(state kind meta_mode meta_margin_mode stock_kind)

  include Balance::Base
  include LibEnums
  include LibControl
  
  # after_create :register_resource_plan
  # after_save :insert_instruments

  # default_scope { where(deleted_at: nil) }

  scope :not_deleted,  -> { where(deleted_at:nil) }
  scope :control_store, ->(store) { where(store: store )}

  enum state:             {disable: 0, enable: 1}
  enum kind:              {slave: 0,   copy: 1}
  enum meta_mode:         {demo: 0,    real: 1}
  enum meta_margin_mode:  {netting: 0, hedging: 1}
  enum stock_kind:        {b3: 0,      forex: 1, usa:2, others:4}

  store :settings, accessors: [:magics_accept, :instrument_control]

  belongs_to :store
  belongs_to :customer
  belongs_to :account_server, optional: true

  has_many :plan_usages, as: :resourceable

  has_many :permissions, dependent: :destroy
  has_many :traces,       through: :permissions#, source: :trace 

  has_many :instruments,                    dependent: :destroy
  has_many :loggings,      as: :loggerable, dependent: :destroy

  has_many :balances,     dependent: :destroy, autosave: true
  has_many :orders,       through: :balances, source: :order,         dependent: :destroy, autosave: true
  has_many :transactions, through: :orders,   source: :transactions,  dependent: :destroy
  has_many :slaves,       ->(account) { where("transaction_slaves.account_id = ?", account.id).distinct },
                           through: :orders, source: :slaves,         dependent: :destroy

  validates_presence_of :name
  validates_uniqueness_of :name, scope: :account_server_id, if: Proc.new { |b| b.account_server_id.present? }

  # def register_resource_plan
  #   store.register_resource_plan(self, self.kind)
  # end

  def self.account_search(current_user)
    if current_user.userable.administrator?
      self.all.map{|x| [x.name, x.id]}   
    else
      self.control_store(current_user.store).order('name desc').map{|x| [x.name, x.id]} 
    end
  end

  def admin_label
    name.upcase
  end

  #libcontrol was calling this method
  def soft_destroy_custom
    self.trace_ids = nil
  end

  # def soft_restore
  #   self.update(deleted_at: nil)
  # end
  
  def api_server_hostname(params)
    if params[:EnvironmentLocal] == "0"
      'signalforex.imentore.com.br'
    elsif params[:EnvironmentLocal] == "1"
      if params[:expert_name] == 'signal_copy'
        'signallocal.imentore.com.br:8080'
      else
        'signallocal.imentore.com.br:80'
      end
    end    
  end

  def trace_copy
    traces.find_by(kind: :copy) if self.copy?
  end

  def sum_slaves_volume(transaction_id)
    slaves.joins(:master).where("transaction_slaves.transaction_id=#{transaction_id}", account_id:self.id).map(&:lot).map(&:to_f).reduce(:+)
  end

  def insert_instruments
    if self.slave?
      Instrument::SYMBOLLIST.each do |symbol|
        self.instruments.create(symbol: symbol[:symbol], name: symbol[:name], volumes:symbol[:volumes], store: self.store)
      end
    end
  end

  def instrument_volume(symbol, value=0)
    instrument = instruments.find_by(symbol: symbol)
    begin
      instrument.volumes.try(:split,', ')[value]
    rescue
      store.volume_default
    end
  end

  def instrument(symbol)
    instrument_control.to_b ? instruments.find_by(symbol: symbol.try(:upcase)).try(:name) : symbol
  end

  def slave_profit
    masters_filter(slaves.closed).to_a.sum(&:profit)
  end

  def slaves_scope(type = :slaves, scope = :all, trace)
    table_name = type == :slaves ? "transaction_slaves" : "transactions"
    # masters_filter(self.send(type).closed.where("transaction_slaves.trace_id = ?", trace.id)).send(scope)
    masters_filter(self.send(type).send(scope).where("#{table_name}.trace_id = ?", trace.id))
  end
  
  def masters_filter(scoped)
    if self.search_date_begin and self.search_date_end
      scoped.where(closed_at: search_date_begin..search_date_end.end_of_day)
    else
      scoped
    end
  end

  def profit_trade(type = :slaves, trace)
    trades = slaves_scope(type, :closed, trace).try(:size).to_f
    gain_trades = slaves_scope(type, :closed, trace).try(:gain).try(:size).to_f
    AlgoStatistic.profit_trade(trades, gain_trades)
  end

  def loss_trade(type = :slaves, trace)
    trades = slaves_scope(type, :closed, trace).try(:size).to_f
    loss_trades = slaves_scope(type, :closed, trace).try(:loss).try(:size).to_f
    AlgoStatistic.loss_trade(trades, loss_trades)
  end

  def pay_off(type = :slaves, trace)
    gain = slaves_scope(type, :closed, trace).try(:gain).to_a.sum(&:profit).abs
    gain_operation = slaves_scope(type, :closed, trace).try(:gain).try(:size).to_f
    loss = slaves_scope(type, :closed, trace).try(:loss).to_a.sum(&:profit).abs
    loss_operation = slaves_scope(type, :closed, trace).try(:loss).try(:size).to_f
    AlgoStatistic.pay_off(gain, gain_operation, loss, loss_operation)
  end

  def expect_pay_off(type = :slaves, trace)
    total_trades = slaves_scope(type, :closed, trace).try(:size)
    profit_trades = slaves_scope(type, :closed, trace).try(:gain).try(:size).to_f
    loss_trades = slaves_scope(type, :closed, trace).try(:loss).try(:size).to_f
    gross_profit = slaves_scope(type, :closed, trace).try(:gain).to_a.sum(&:profit).abs
    gross_loss = slaves_scope(type, :closed, trace).try(:loss).to_a.sum(&:profit).abs
    AlgoStatistic.expect_pay_off(profit_trades, total_trades, gross_profit, loss_trades, gross_loss)
  end

  def profit_factor(type = :slaves, trace)
    gross_profit = slaves_scope(type, :closed, trace).try(:gain).to_a.sum(&:profit).abs
    gross_loss = slaves_scope(type, :closed, trace).try(:loss).to_a.sum(&:profit).abs
    AlgoStatistic.profit_factor(gross_profit, gross_loss, pay_off(type, trace)).abs
  end

  def profit_drawdown(type = :slaves, trace)
    gain = self.slaves_scope(type, :closed, trace).try(:gain).to_a.sum(&:profit).abs
    loss = self.slaves_scope(type, :closed, trace).try(:loss).to_a.sum(&:profit).abs
    profit = gain - loss
    AlgoStatistic.profit_drawdown(profit, drawdown(type, trace)).abs
  end

  def drawdown(type = :slaves, trace)
    scoped = slaves_scope(type, :closed, trace).order(closed_at: :desc)
    AlgoStatistic.drawdown(scoped)
  end

end