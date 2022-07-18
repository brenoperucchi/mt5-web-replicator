require 'lib_enums'
class Account < ApplicationRecord
  ENUMS = %w(state kind meta_mode meta_margin_mode)

  include Balance::Base
  include LibEnums
  
  after_create :insert_instruments

  enum state: {disable: 0, enable: 1}
  enum kind:  {slave: 0, copy: 1}
  enum meta_mode:         {demo: 0, real: 1}
  enum meta_margin_mode:  {netting: 0, hedging: 1}

  store :settings, accessors: [:magics_accept, :instrument_control]

  belongs_to :store
  belongs_to :customer

  has_many :permissions
  has_many :traces,       through: :permissions#, source: :trace 
  # has_many :orders,       through: :traces, source: :orders
  
  has_many :instruments,                    dependent: :destroy
  has_many :loggings,      as: :loggerable, dependent: :destroy
  
  has_many :deals
  
  has_many :balances
  has_many :orders,       through: :balances, source: :order,         dependent: :destroy
  has_many :transactions, through: :orders,   source: :transactions,  dependent: :destroy
  # has_many :slaves,       through: :orders,   source: :slaves,        dependent: :destroy
  has_many :slaves,        class_name: 'TransactionSlave', foreign_key: 'account_id'

  def trace_copy
    traces.find_by(kind: :copy) if self.copy?
  end

  def sum_slaves_volume(transaction_id)
    slaves.joins(:master).where("transaction_slaves.transaction_id=#{transaction_id}", account_id:self.id).map(&:lot).map(&:to_f).reduce(:+)
  end

  def insert_instruments
    if self.slave?
      Instrument::SYMBOLLIST.each do |symbol|
        self.instruments.create(symbol: symbol[:symbol], name: symbol[:name], volumes:symbol[:volumes])
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


  def profit_trade(type = :slaves)
    trades = self.send(type).closed.try(:count).to_f
    gain_trades = self.send(type).closed.try(:gain).try(:count).to_f
    AlgoStatistic.profit_trade(trades, gain_trades)
  end

  def loss_trade(type = :slaves)
    trades = self.send(type).closed.try(:count).to_f
    loss_trades = self.send(type).closed.try(:loss).try(:count).to_f
    AlgoStatistic.loss_trade(trades, loss_trades)
  end

  def pay_off(type = :slaves)
    gain = self.send(type).closed.try(:gain).sum(:profit).abs
    gain_operation = self.send(type).closed.try(:gain).try(:count).to_f
    loss = self.send(type).closed.try(:loss).sum(:profit).abs
    loss_operation = self.send(type).closed.try(:loss).try(:count).to_f
    AlgoStatistic.pay_off(gain, gain_operation, loss, loss_operation)
  end

  def profit_factor(type = :slaves)
    AlgoStatistic.profit_factor(profit_trade(type), loss_trade(type), pay_off(type))
  end


  def drawdown(type = :slaves)
    AlgoStatistic.drawdown(self.send(type).closed)
  end


end