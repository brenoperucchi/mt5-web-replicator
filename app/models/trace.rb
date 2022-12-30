require 'lib_enums'
require 'algo_statistic'

class Trace < ApplicationRecord

  attr_accessor :search_date_begin, :search_date_end

  ENUMS = %w(kind)

  include LibEnums
  include AlgoStatistic

  enum kind:  {telegram: 0, copy: 1}

  store :settings, accessors: [:telegram_option, :telegram_image, :take_profit_limit, 
                               :telegram_api_id, :telegram_api_hash, :telegram_api_number, :copy_control_instrument, :restrict_control_instrument]

  # has_many :deals, dependent: :destroy
  # has_many :masters, :through => :deals, :source => :masters
  # has_many :slaves,  :through => :deals, :source => :slaves

  has_many :orders, dependent: :destroy
  has_many :transactions#, :through => :orders, :source => :transactions
  has_many :masters, :through => :orders, :source => :transactions
  has_many :slaves,  :through => :orders, :source => :slaves


  has_many :messages, :class_name => "Message::Message", :foreign_key => "trace_id"

  has_many :instruments, :class_name => "Instrument", :foreign_key => "trace_id", dependent: :destroy
  belongs_to :store, optional: true

  scope :active,   ->{ where.not(active_at:nil)}
  # scope :telegram, ->{ where(kind:'telegram')}

  has_many :permissions, dependent: :destroy
  has_many :accounts, :through => :permissions#, :source => :slave

  validates_presence_of   [:name, :name_id]
  validates_uniqueness_of [:name, :name_id], scope: :store_id

  def volumes
    self.settings['volumes'] || ""
  end

  def active
    active_at.present?
  end

  def active=(value)
    self.active_at = (value == "1") ? Time.current : nil
  end

  alias_method :active?, :active

  def off 
    self.update_column(:active_at, nil)
  end

  def self.disable
    Trace.all.map(&:off)
  end

  def masters_transactions
    masters_scope(:masters)
  end

  # def masters_total
  #   masters_filter(masters)
  # end



  def create_orders(order_params, account, message, symbol)
    ticket = order_params['order_id']
    instrument = check_instrument(account, symbol)
    api_transaction_attributes = SerializerAPITransaction.new(order_params).api_attributes.merge(symbol: instrument, profit:nil, message: message, trace: self, account:account)
    if account.netting?
      order = account.orders.where(symbol: instrument).where.not(state: [:closed, :pending]).try(:last)
      if order.nil?
        order = account.orders.create(message: message, trace: self, content_id:ticket, symbol: instrument, account:account, store:self.store) 
      end
      transaction = order.transactions.find_by(symbol: instrument, account: account)
      transaction ||= order.transactions.create(api_transaction_attributes.merge(account:account))
    elsif account.hedging?
      order = account.orders.create_with(trace: self, message: message, content_id: ticket, symbol:instrument, account: account, store: self.try(:store)).find_or_create_by(content_id: ticket)
      transaction = order.transactions.create_with(api_transaction_attributes).find_or_create_by(ticket: ticket)
    end

    # CREATE ORDER -> TRANSACTION -> SLAVES
    if order.valid?
      order.execute
    end

    if order and not order.error?
      transaction.loggings.new(content:order_params, changeset: transaction.try(:versions).try(:last).try(:changeset), state: "OPEN")
      transaction.execute
      if transaction and not transaction.error?
        return true if account.netting? and order.slaves.count > 0 
        self.accounts.slave.enable.each do |account|
          order.accounts << account
          # instrument = check_instrument(account, symbol)
          api_attributes = SerializerAPITransactionSlave.new(order_params).api_attributes.merge(symbol: instrument, price_request:order_params['price'], profit:nil, account:account, price_open:nil, comment: ticket)
          slave = order.slaves.create(api_attributes.merge(symbol:instrument, comment: ticket, account:account, master:transaction, trace: self))
        end

      end
    end
  end

  def check_instrument(account, symbol)
    if copy_control_instrument.to_b
      account.instruments.find_by(symbol: symbol.try(:upcase)).try(:name) || symbol
    elsif account.instrument_control.to_b
      account.instruments.find_by(symbol: symbol.try(:upcase)).try(:name) || symbol
    else 
      symbol
    end
  end

  def masters_scope(type = :masters, scope = :all)
    masters_filter(self.send(type).send(scope))
  end

  def masters_filter(scoped)
    if self.search_date_begin and self.search_date_end
      scoped.where(created_at: search_date_begin..search_date_end.end_of_day)
    else
      scoped
    end
  end

  def profit_trade(type = :masters)
    trades = masters_scope(:masters, :closed).try(:count).to_f
    gain_trades = masters_scope(:masters, :closed).try(:gain).try(:count).to_f
    AlgoStatistic.profit_trade(trades, gain_trades)
  end

  def loss_trade(type = :masters)
    trades = masters_scope(:masters, :closed).try(:count).to_f
    loss_trades = masters_scope(:masters, :closed).try(:loss).try(:count).to_f
    AlgoStatistic.loss_trade(trades, loss_trades)
  end

  def pay_off(type = :masters)
    gain = masters_scope(:masters, :closed).try(:gain).sum(:profit).abs
    gain_operation = masters_scope(:masters, :closed).try(:gain).try(:count).to_f
    loss = masters_scope(:masters, :closed).try(:loss).sum(:profit).abs
    loss_operation = masters_scope(:masters, :closed).try(:loss).try(:count).to_f
    AlgoStatistic.pay_off(gain, gain_operation, loss, loss_operation)
  end

  def expect_pay_off(type = :masters)
    total_trades = masters_scope(type, :closed).count
    profit_trades = masters_scope(type, :closed).try(:gain).count.to_f
    loss_trades = masters_scope(type, :closed).try(:loss).count.to_f
    gross_profit = masters_scope(type, :closed).try(:gain).sum(:profit).abs
    gross_profit = masters_scope(type, :closed).try(:gain).sum(:profit).abs
    gross_loss = masters_scope(type, :closed).try(:loss).sum(:profit).abs
    AlgoStatistic.expect_pay_off(profit_trades, total_trades, gross_profit, loss_trades, gross_loss)
  end

  def profit_factor(type = :masters)
    gross_loss = masters_scope(type, :closed).try(:loss).sum(:profit).abs
    gross_profit = masters_scope(type, :closed).try(:gain).sum(:profit).abs
    AlgoStatistic.profit_factor(gross_profit, gross_loss, pay_off(type))
  end

  def drawdown(type = :masters)
    scoped = masters_scope(:masters, :closed).order(created_at: :desc)
    AlgoStatistic.drawdown(scoped)
  end

end