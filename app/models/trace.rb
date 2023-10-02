require 'lib_enums'
require 'algo_statistic'

class Trace < ApplicationRecord

  attr_accessor :search_date_begin, :search_date_end

  ENUMS = %w(kind)

  include LibEnums
  include AlgoStatistic
  include LibControl

  enum kind:  {telegram: 0, copy: 1}

  store :settings, accessors: [
                                :telegram_option, :telegram_image, :take_profit_limit, 
                                :telegram_api_id, :telegram_api_hash, :telegram_api_number, 
                                :instrument_control, :restrict_control_instrument, :magics_accept, :description, :capital_recomendation, :contract_volume_max,
                                :stock_kind, :capital_multiplier
                              ]

  has_many :orders
  has_many :transactions
  has_many :statitics, through: :transactions, source: :statistics
  has_many :masters, :through => :orders, :source => :transactions
  has_many :slaves,  :through => :orders, :source => :slaves

  # has_many :messages, :class_name => "Message::Message", :foreign_key => "trace_id"
  has_and_belongs_to_many :messages, :class_name => "Message::Message"

  has_many :instruments, :class_name => "Instrument", :foreign_key => "trace_id", dependent: :destroy
  belongs_to :store, optional: true

  scope :active,   ->{ where.not(active_at:nil)}
  scope :not_deleted,  -> { where(deleted_at:nil) }
  # scope :telegram, ->{ where(kind:'telegram')}

  has_many :permissions#, dependent: :destroy
  has_many :accounts, :through => :permissions#, :source => :slave
  has_many :customer_plans, :through => :permissions#, :source => :slave

  
  has_one :permission#, dependent: :destroy
  has_one :customer_plan, :through => :permission, :source => :customer_plan

  # accepts_nested_attributes_for :payment

  validates_presence_of   [:name, :name_id]
  validates_presence_of   [:contract_volume_max, :customer_plans]
  validates_uniqueness_of [:name_id], scope: :store_id
  validates :capital_recomendation, format: { with: /\A\d+([.,]\d{3})*([.,]\d+)?\z/, message: 'must be a number' }, allow_blank: true

  validate  :associated_with_customer_plan_and_amount_greater_than_zero, on: :update

  def capital_recomedation=(value)
    value = value.to_s.gsub(".", "").gsub(",", ".")
    self.settings['capital_recomendation'] = value
  end


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

  def magic_number_restrict?
    Order.magic_numbers_split(self.magics_accept) or Order.magic_numbers_split(accounts.copy.map(&:magics_accept)).present?
  end

  def create_order(order_params, account, message, symbol, api_version)

    apiCopySerializerClass = Class.const_get("API::#{api_version.try(:upcase)}::APICopySerializer")

    ticket = order_params['ticket_id']
    instrument = check_instrument(account, symbol)
    
    copy_attributes = apiCopySerializerClass.new(order_params).copy_attributes.merge(symbol: instrument, message: message, trace: self, account:account)

    if account.netting?
      order = account.orders.where(symbol: instrument).where.not(state: [:closed, :pending]).try(:last)
      if order.nil?
        order = account.orders.create(messages: [message], message: message, trace: self, content_id:ticket, symbol: instrument, account:account, store:self.store) 
      end
      transaction = order.transactions.find_by(symbol: instrument, account: account)
      transaction ||= order.transactions.create(copy_attributes.merge(account:account))
    elsif account.hedging?
      order = account.orders.create_with(trace: self, messages: [message], message: message, content_id: ticket, symbol:instrument, account: account, store: self.try(:store)).find_or_create_by(content_id: ticket, trace:self)
      transaction = order.transactions.create_with(copy_attributes).find_or_create_by(ticket: ticket, trace:self)
    end

    # api_transaction = apiCopySerializerClass.new(order_params)
    transaction.update_mfe_mae(copy_attributes[:mfe], copy_attributes[:mae], copy_attributes[:time_trader]) 

    # CREATE ORDER -> TRANSACTION -> SLAVES
    if order.valid?
      order.execute
    end

    if order and not order.error?
      transaction.loggings.create(loggerable:message, content:order_params, changeset: transaction.try(:versions).try(:last).try(:changeset), state: "OPEN", parent: message.loggings.first, account: account)
      transaction.execute
      if transaction and not transaction.error?
        return true if account.netting? and order.slaves.count > 0 
        self.accounts.slave.enable.each do |account_slave|
          
          instrument = check_instrument(account, symbol, account_slave)
          slave_attributes = SerializerAPITransactionSlave.new(order_params).trace_attributes(instrument, account_slave, transaction, self)
          slave = order.slaves.new(slave_attributes)
          if slave.save
            order.accounts << account_slave
            slave.loggings.create(loggerable:message, content:order_params, changeset: slave.try(:versions).try(:last).try(:changeset), state: "CREATE", parent: message.loggings.first, account: account_slave)
          else
            message.loggings.create(content: "Error create Slave - Order #{order.id} - Account #{account_slave.id}", changeset: transaction.try(:versions).try(:last).try(:changeset), state: "ERROR", parent: message.loggings.first, account: account, resourceable:order)
          end
        end

      end
    end

    return order.executed? && transaction.executed?
  end

  def check_instrument(account, symbol, account_slave=nil)
    if account_slave and self.instrument_control.to_b
      instrument = account_slave.instruments.find_by(symbol: symbol.try(:upcase)).try(:name) if account_slave.instrument_control.to_b
      instrument ||= account.instruments.find_by(symbol: symbol.try(:upcase)).try(:name) if account.instrument_control.to_b
    end
    instrument || symbol
  end


  def restrict_magic_number(resource)
    unless self.magics_accept.blank?
      trace_magic_number = self.try(:trace).try(:name_id)
      magic_numbers = Order.magic_numbers_split(self.magics_accept)
      changeset = resource.try(:versions).try(:last).try(:changeset)
      version = resource.try(:version)
      unless magic_numbers.detect{|x| x == resource.magic_number}
        resource.loggings.create(content:"#{self.class.name} ##{resource.id} has magic number #{resource.magic_number} and trace: #{resource.try(:account).try(:name)} accepted: #{magic_numbers.join(" - ")}", changeset: changeset, version:version, state: 'ERROR', parent:resource.order.message.loggings.first)
        resource.erro!
      end
    end
    resource.error?
  end  

  def mfe
    if self.search_date_begin and self.search_date_end
      self.statitics.mfe_max(self.search_date_begin..self.search_date_end.try(:end_of_day))
    else
      self.statitics.mfe_max
    end
    #   self.statitics.group_day_amount(:mfe, search_date_begin..search_date_end.end_of_day)
    # else
    #   self.statitics.group_day_amount(:mfe)
    # end
  end

  def mae    
    if self.search_date_begin and self.search_date_end
      self.statitics.mae_min(self.search_date_begin..self.search_date_end.try(:end_of_day))
    else
      self.statitics.mae_min
    end
    # if self.search_date_begin and self.search_date_end
    #   self.statitics.group_day_amount(:mfe, search_date_begin..search_date_end.end_of_day)
    # else
    #   self.statitics.group_day_amount(:mfe)
    # end
  end

  def masters_scope(type = :masters, scope = :all)
    data = masters_filter(self.send(type), scope)
    if scope.is_a?(Array)
      data = data.send(:instance_eval, "#{scope.join(".").to_s}")
    else
      data = data.send(scope) if data.respond_to?(scope)
    end

    if magic_number_restrict?
      magics = Order.magic_numbers_split(self.magics_accept)
      magics ||= Order.magic_numbers_split(accounts.copy.map(&:magics_accept))
      
      magics = magics.map(&:to_i)
      data = data.where(magic_number:[magics])
    end

    data
  end

  def profit_masters
    @profit_masters = masters_scope(:masters, :closed).to_a.sum(&:profit)
    @profit_masters
  end


  def masters_filter(data, scope = nil)
    # if Rails.env.development?
    #   self.search_date_begin = Date.parse("2023-09-01").to_date 
    #   self.search_date_end   = DateTime.now
    # end
    if self.search_date_begin and self.search_date_end
      if scope == :executed or scope == :all or (scope.is_a?(Array) and scope.include?(:executed))
        query = {:created_at => search_date_begin..search_date_end.end_of_day}
      else
        query = {:closed_at => search_date_begin..search_date_end.end_of_day}
      end
      data = data.where(query)
    end
    data
  end

  def profit_trade(type = :masters)
    trades = masters_scope(type, :closed).try(:count).to_f
    gain_trades = masters_scope(type, :closed).try(:gain).try(:count).to_f
    AlgoStatistic.profit_trade(trades, gain_trades)
  end

  def loss_trade(type = :masters)
    trades = masters_scope(type, :closed).try(:count).to_f
    loss_trades = masters_scope(type, :closed).try(:loss).try(:count).to_f
    AlgoStatistic.loss_trade(trades, loss_trades)
  end

  def pay_off(type = :masters)
    gain = masters_scope(type, :closed).try(:gain).to_a.sum(&:profit).abs
    gain_operation = masters_scope(type, :closed).try(:gain).try(:count).to_f
    loss = masters_scope(type, :closed).try(:loss).to_a.sum(&:profit).abs
    loss_operation = masters_scope(type, :closed).try(:loss).try(:count).to_f
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
    gain = self.masters_scope(type, :closed).try(:gain).to_a.sum(&:profit).abs
    loss = self.masters_scope(type, :closed).try(:loss).to_a.sum(&:profit).abs
    profit = gain - loss
    AlgoStatistic.profit_drawdown(profit, drawdown).abs
  end

  def drawdown(type = :masters)
    scoped = masters_scope(type, :closed).order(closed_at: :asc)
    AlgoStatistic.drawdown(scoped)
  end

  def drawdown_dates(type = :masters)
    scoped = masters_scope(type, :closed).order(closed_at: :asc)
    AlgoStatistic.drawdown_dates(scoped)
  end

  def average(type = :masters, scope)
    scoped = masters_scope(type, scope) 
    return 0 if scoped.size == 0
    scoped.sum(&:profit) / scoped.size
  end

  def next_charged
    days = DateTime.now.day > 15 ? 15 : 0
    (DateTime.now + days + CustomerPlan.charge_recurrences[customer_plan.charge_recurrence.to_s].months).beginning_of_month
  end


  private 

  def associated_with_customer_plan_and_amount_greater_than_zero
    # customer_plans = self.customer_plans).flatten

    if self.customer_plan.nil?
      errors.add(:base, 'Trace must be associated with a CustomerPlan')
    # elsif customer_plans.any? { |cp| cp.amount <= 0 }
    elsif customer_plan.amount_use <= 0 || customer_plan.amount.nil?
      errors.add(:base, 'Associated CustomerPlan must have an amount greater than 0')
    end
  end




  # def test_drawdown
  #   self.search_date_begin = DateTime.parse("12 Mar 2023 00:00:00 -0300")
  #   self.search_date_end   = DateTime.parse("12 Abr 2023 00:00:00 -0300")
  #   collection = self.masters_scope(:masters, :closed)
  #   drawdown_dates(drawdown_dates)
  # end

end