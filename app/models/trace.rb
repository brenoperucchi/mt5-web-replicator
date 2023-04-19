require 'lib_enums'
require 'algo_statistic'

class Trace < ApplicationRecord

  attr_accessor :search_date_begin, :search_date_end, :dashboard_magic_number

  ENUMS = %w(kind)

  include LibEnums
  include AlgoStatistic
  include LibControl

  enum kind:  {telegram: 0, copy: 1}

  store :settings, accessors: [
                                :telegram_option, :telegram_image, :take_profit_limit, 
                                :telegram_api_id, :telegram_api_hash, :telegram_api_number, 
                                :instrument_control, :restrict_control_instrument, :magics_accept
                              ]

  has_many :orders
  has_many :transactions
  has_many :masters, :through => :orders, :source => :transactions
  has_many :slaves,  :through => :orders, :source => :slaves

  # has_many :messages, :class_name => "Message::Message", :foreign_key => "trace_id"
  has_and_belongs_to_many :messages, :class_name => "Message::Message"

  has_many :instruments, :class_name => "Instrument", :foreign_key => "trace_id", dependent: :destroy
  belongs_to :store, optional: true

  scope :active,   ->{ where.not(active_at:nil)}
  scope :not_deleted,  -> { where(deleted_at:nil) }
  # scope :telegram, ->{ where(kind:'telegram')}

  has_many :permissions, dependent: :destroy
  has_many :accounts, :through => :permissions#, :source => :slave

  validates_presence_of   [:name, :name_id]
  validates_uniqueness_of [:name, :name_id], scope: :store_id

  def soft_destroy_custom
    self.update_column(:active_at, nil)
  end

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



  # def off 
  #   self.update_column(:active_at, nil)
  # end

  # def self.disable
  #   Trace.all.map(&:off)
  # end

  def masters_transactions
    masters_scope(:masters)
  end

  # def masters_total
  #   masters_filter(masters)
  # end

  def create_orders(order_params, account, message, symbol)
    ticket = order_params['ticket_id']
    instrument = check_instrument(account, symbol)
    api_transaction_attributes = SerializerAPITransaction.new(order_params).api_attributes.merge(symbol: instrument, message: message, trace: self, account:account)
    if account.netting?
      order = account.orders.where(symbol: instrument).where.not(state: [:closed, :pending]).try(:last)
      if order.nil?
        order = account.orders.create(message: message, trace: self, content_id:ticket, symbol: instrument, account:account, store:self.store) 
      end
      transaction = order.transactions.find_by(symbol: instrument, account: account)
      transaction ||= order.transactions.create(api_transaction_attributes.merge(account:account))
    elsif account.hedging?
      order = account.orders.create_with(trace: self, message: message, content_id: ticket, symbol:instrument, account: account, store: self.try(:store)).find_or_create_by(content_id: ticket, trace:self)
      transaction = order.transactions.create_with(api_transaction_attributes).find_or_create_by(ticket: ticket, trace:self)
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
        self.accounts.slave.enable.each do |account_slave|
          
          instrument = check_instrument(account, symbol, account_slave)
          api_attributes = SerializerAPITransactionSlave.new(order_params).api_attributes.merge(symbol: instrument, price_request:order_params['price'], profit:nil, account:account_slave, price_open:nil, comment: ticket)
          if order.slaves.create(api_attributes.merge(symbol:instrument, comment: ticket, account:account_slave, master:transaction, trace: self))
            order.accounts << account_slave
          end
        end

      end
    end
  end

  def check_instrument(account, symbol, account_slave=nil)
    if account_slave and self.instrument_control.to_b
      instrument = account_slave.instruments.find_by(symbol: symbol.try(:upcase)).try(:name) if account_slave.instrument_control.to_b
      instrument ||= account.instruments.find_by(symbol: symbol.try(:upcase)).try(:name) if account.instrument_control.to_b
    end
    instrument || symbol
  end

  def masters_scope(type = :masters, scope = :all)
    data = masters_filter(self.send(type))
    if scope.is_a?(Array)
      data = data.send(:instance_eval, "#{scope.join(".").to_s}")
    else
      data = data.send(scope) if data.respond_to?(scope)
    end

    if self.try(:dashboard_magic_number)
      magics   = Order.magic_numbers_split(self.magics_accept)
      magics ||= Order.magic_numbers_split(accounts.copy.map(&:magics_accept))

      if magics.present?
        magics = magics.map(&:to_i)
        data = data.where(magic_number:[magics])
      end
    end

    data
  end

  def restrict_magic_number(resource)
    unless self.magics_accept.blank?
      trace_magic_number = self.try(:trace).try(:name_id)
      magic_numbers = Order.magic_numbers_split(self.magics_accept)
      changeset = resource.try(:versions).try(:last).try(:changeset)
      version = resource.try(:version)
      unless magic_numbers.detect{|x| x == resource.magic_number}
        resource.loggings.create(content:"#{self.class.name} ##{resource.id} has magic number #{resource.magic_number} and the account: #{resource.try(:account).try(:name)} accepted: #{magic_numbers.join(" - ")}", changeset: changeset, version:version, state: 'ERROR')
        resource.erro!
      end
    end
    resource.error?
  end  


  def masters_filter(scoped)
    if self.search_date_begin and self.search_date_end
      scoped.where(closed_at: search_date_begin..search_date_end.end_of_day)
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
    gain = masters_scope(:masters, :closed).try(:gain).to_a.sum(&:profit).abs
    gain_operation = masters_scope(:masters, :closed).try(:gain).try(:count).to_f
    loss = masters_scope(:masters, :closed).try(:loss).to_a.sum(&:profit).abs
    loss_operation = masters_scope(:masters, :closed).try(:loss).try(:count).to_f
    AlgoStatistic.pay_off(gain, gain_operation, loss, loss_operation)
  end

  def expect_pay_off(type = :masters)
    total_trades = masters_scope(type, :closed).count
    profit_trades = masters_scope(type, :closed).try(:gain).count.to_f
    loss_trades = masters_scope(type, :closed).try(:loss).count.to_f
    gross_profit = masters_scope(type, :closed).try(:gain).to_a.sum(&:profit).abs
    gross_loss = masters_scope(type, :closed).try(:loss).to_a.sum(&:profit).abs
    AlgoStatistic.expect_pay_off(profit_trades, total_trades, gross_profit, loss_trades, gross_loss)
  end

  def profit_factor(type = :masters)
    gross_profit = masters_scope(type, :closed).try(:gain).to_a.sum(&:profit).abs
    gross_loss = masters_scope(type, :closed).try(:loss).to_a.sum(&:profit).abs
    AlgoStatistic.profit_factor(gross_profit, gross_loss, pay_off(type)).abs
  end

  def profit_drawdown(type = :masters)
    gain = self.masters_scope(:masters, :closed).try(:gain).to_a.sum(&:profit).abs
    loss = self.masters_scope(:masters, :closed).try(:loss).to_a.sum(&:profit).abs
    profit = gain - loss
    AlgoStatistic.profit_drawdown(profit, drawdown).abs
  end

  def drawdown(type = :masters)
    scoped = masters_scope(:masters, :closed).order(closed_at: :asc)
    AlgoStatistic.drawdown(scoped)
  end

  def drawdown_dates(type = :masters)
    scoped = masters_scope(:masters, :closed).order(closed_at: :asc)
    AlgoStatistic.drawdown_dates(scoped)
  end

  def average(type = :masters, scope)
    scoped = masters_scope(type, scope) 
    return 0 if scoped.size == 0
    scoped.sum(&:profit) / scoped.size
  end

  def dashboard_capital_accumulated
    amount_total = 0
    collection = masters_scope(:masters, :closed).order(closed_at: :asc)
    collection_array = []
    if collection.present?
      collection_array = [{day:(collection.first.closed_at - 1.day).strftime("%Y-%m-%d"), portfolio: 0, profit: 0, loss:0}]
      (collection.first.closed_at.to_datetime..collection.last.closed_at.to_datetime).each do |date|
        profit = collection.where(closed_at: date.beginning_of_day..date.end_of_day).sum(&:profit)
        amount_total = profit + amount_total
        profit_value = profit <= 0 ? 0 : profit
        loss_value = profit >= 0 ? 0 : profit
        collection_array.push({day:date.strftime("%Y-%m-%d"), portfolio: amount_total.to_f, profit: profit_value.to_f, loss:loss_value.to_f})
      end
    end
    collection_array
  end

  def dashboard_drawdown
    amount_total = 0
    collection = masters_scope(:masters, :closed).order(closed_at: :asc)
    collection_array = []
    if collection.present?
      collection_array = [{day:(collection.first.closed_at - 1.day).strftime("%Y-%m-%d"), drawdown: 0}]
      (collection.first.closed_at.to_datetime..collection.last.closed_at.to_datetime).each do |date|
        records = collection.where(closed_at: date.beginning_of_day..date.end_of_day)
        drawdown = AlgoStatistic.drawdown(records)
        collection_array.push({day:date.strftime("%Y-%m-%d"), drawdown: drawdown})
      end
    end
    collection_array
  end

  def dashboard_monthy_amount
    amount_total = 0
    date    = ['date']
    capital = ['capital']
    profit  = ['profit']
    array = []
    self.transactions.closed.order('closed_at asc').group_by{|x| x.closed_at.beginning_of_month.strftime("%b/%Y")}.map do |k,v|
      amount_total = v.sum(&:profit) + amount_total
      {date:k, capital: amount_total, profit: v.sum(&:profit)} 
    end
  end


  # def drawdown_days(type = :masters)
  #   scoped = masters_scope(:masters, :closed).order(closed_at: :asc)
  #   AlgoStatistic.drawdown_days(scoped)
  # end

  # def test_drawdown
  #   self.search_date_begin = DateTime.parse("12 Mar 2023 00:00:00 -0300")
  #   self.search_date_end   = DateTime.parse("12 Abr 2023 00:00:00 -0300")
  #   collection = self.masters_scope(:masters, :closed)
  #   drawdown_dates(drawdown_dates)
  # end

end