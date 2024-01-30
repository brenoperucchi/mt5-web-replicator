require 'thread' # Importe a biblioteca de semáforos
require 'lib_enums' # Path: lib/lib_enums.rb
require 'algo_statistic' # Path: lib/algo_statistic.rb

class Trace < ApplicationRecord
  attr_accessor :search_date_begin, :search_date_end, :search_magic_number

  include LibEnums
  include AlgoStatistic
  include LibControl

  enum kind:      { telegram: 0, copy:     1 }
  enum kind_copy: { normal:   0, prop_firm:1 }

  serialize :mfe_analyzed

  store :settings, accessors: [
                                :telegram_option, :telegram_image, :take_profit_limit,
                                :telegram_api_id, :telegram_api_hash, :telegram_api_number,
                                :instrument_control, :restrict_control_instrument, :magics_accept, :desc_contract, :capital_recomendation, :contract_volume_max,
                                :stock_kind, :capital_multiplier, :magic_same, :desc_finish
                              ]

  has_many :orders
  has_many :transactions
  has_many :statitics, through: :transactions, source: :statistics
  has_many :masters,   through: :orders, source: :transactions
  has_many :slaves,    through: :orders, source: :slaves

  has_and_belongs_to_many :messages, class_name: "Message::Message"

  has_many :instruments, class_name: "Instrument", foreign_key: "trace_id", dependent: :destroy
  belongs_to :store, optional: true

  scope :active,   ->{ where.not(active_at:nil)}
  scope :not_deleted,  -> { where(deleted_at:nil) }
  # scope :telegram, ->{ where(kind:'telegram')}

  has_many :permissions#, dependent: :destroy
  has_many :accounts,       through: :permissions#, source: :slave
  has_many :customer_plans, through: :permissions#, source: :slave

  
  has_one :permission#, dependent: :destroy
  has_one :customer_plan,  through: :permission, source: :customer_plan

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
    data_scope(:masters)
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
          slave.magic_number = check_magic_number(slave_attributes[:magic_number])
          if self.prop_firm?
            slave.comment      = "#{account_slave.id}#{slave.magic_number}_#{slave.comment}"
            slave.magic_number = "#{account_slave.id}#{slave.magic_number}".to_i
          end
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

  def check_magic_number(magic_number)
    self.magic_same.to_b ? magic_number : self.name_id
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
      magic_numbers = Order.magic_numbers_split(self.magics_accept)
      changeset = resource.try(:versions).try(:last).try(:changeset)
      version = resource.try(:version)
      unless magic_numbers.detect{|x| x == resource.magic_number}
        resource.loggings.create(content:"#{self.class.name} ##{resource.id} has magic number #{resource.magic_number} and the trace: #{resource.try(:account).try(:name)} only accepted: #{magic_numbers.join(" - ")}", changeset: changeset, version:version, state: 'ERROR', parent:resource.order.message.loggings.first)
        resource.erro!
      end
    end
    resource.error?
  end

  def next_charged
    days = DateTime.now.day > 15 ? 15 : 0
    (DateTime.now + days + CustomerPlan.charge_recurrences[customer_plan.charge_recurrence.to_s].months).beginning_of_month
  end


  def mfe_analyze(mfe_target = 50, loss_set = 50, grouped_data = nil)
    # if Rails.env.development?
    #   self.search_date_begin = Date.parse("2024-01-01")
    #   self.search_date_end = Date.parse("2024-01-30")
    # end
    values = []
    data ||= self.data_scope.where(state: [:closed, :executed]) if grouped_data.nil?
    grouped_data ||= data.joins(:mfe)
                   .select(:id, :ticket, :profit, :open_at, :closed_at, "statistics.amount AS mfe_value, statistics.created_at AS mfe_created_at")
                   .order(open_at: :asc, id: :asc)
                   .group_by { |x| x[:open_at].to_date }
                   .sort

    grouped_data.each do |date, transactions|
      profit_date = 0
      profit_original = 0
      reach_target = false
      overlapping_transactions = {}
      analyzed_transactions = []
      profit_original = transactions.map(&:profit).sum
      
      transactions.each_with_index do |trans1, index1|
        break if reach_target
        transactions.each do |trans2|
          if trans1.open_at <= trans2.open_at && trans1.mfe_created_at >= trans2.mfe_created_at and trans1.id != trans2.id
            if profit_date >= mfe_target
              reach_target = true
              break
            end
            if profit_date <= (-loss_set.abs)
              reach_target = true
              break
            end

            overlapping_transactions[trans1.ticket] = {}
            overlapping_transactions[trans1.ticket][:transactions] = []
            overlapping_transactions[trans1.ticket][:profit] = 0
            overlapping_transactions[trans1.ticket][:transactions] << trans1 unless overlapping_transactions[trans1.ticket][:transactions].include?(trans1)
            overlapping_transactions[trans1.ticket][:transactions] << trans2 unless overlapping_transactions[trans1.ticket][:transactions].include?(trans2)
            analyzed_transactions << trans1 unless analyzed_transactions.include?(trans1)
            analyzed_transactions << trans2 unless analyzed_transactions.include?(trans2)
            
            if(trans1.mfe_value + trans2.mfe_value >= mfe_target)
              overlapping_transactions[trans1.ticket][:profit] = mfe_target
            else
              overlapping_transactions[trans1.ticket][:profit] = trans1.profit + trans2.profit
              profit_date += trans2.profit
            end

          else
            next if analyzed_transactions.include?(trans2)
            analyzed_transactions << trans2 unless analyzed_transactions.include?(trans2)
            if(trans2.mfe_value >= mfe_target)
              profit_date += mfe_target
            else
              profit_date += trans2.profit
            end

            if profit_date >= mfe_target
              reach_target = true
              break
            end
            if profit_date <= (-loss_set.abs)
              profit_date = -loss_set.abs
              reach_target = true
              break
            end

          end
        end

      break if reach_target
      end

      values << {
        date: date,
        reach_target: reach_target,
        profit_target: mfe_target,
        profit_date: profit_date,
        profit_original: profit_original,
        transactions_overlapping: overlapping_transactions,
        transactions_analyzed: analyzed_transactions.uniq,
      }
    end
    # profit_reach_target = values.sum{|entry| entry[:profit_date]}
    # values <<  {profit_total: profit_reach_target}
    values
  end

  # def test_parameters
  #   data ||= self.data_scope.where(state: [:closed, :executed])
  #   grouped_data = data.joins(:mfe)
  #                  .select(:id, :ticket, :profit, :open_at, :closed_at, "statistics.amount AS mfe_value, statistics.created_at AS mfe_created_at")
  #                  .order(open_at: :asc, id: :asc)
  #                  .group_by { |x| x[:open_at].to_date }
  #                  .sort

  #   results = []

  #   target = (2..30).map{|x| x*10}

  #   target.each do |mfe_target|
  #     target.each do |loss_set|
  #       result = mfe_analyze(mfe_target, loss_set, grouped_data)
  #       # self.search_date_begin = Date.parse("2023-10-01")
  #       # self.search_date_end   = Date.parse("2023-12-30")
  #       performance_metric = mfe_calculate_performance_metric(result)
  #       results << { mfe_target: mfe_target, loss_set: loss_set, performance: performance_metric }
  #     end
  #   end

  #   results.max_by { |r| r[:performance] }
  # end

  require 'thread'

  def test_parameters_parallel(target = nil)
    # self.search_date_begin = Date.parse("2023-12-01")
    # self.search_date_end = Date.parse("2024-01-30")

    data ||= self.data_scope.where(state: [:closed, :executed])
    grouped_data = data.joins(:mfe)
                       .select(:id, :ticket, :profit, :open_at, :closed_at, "statistics.amount AS mfe_value, statistics.created_at AS mfe_created_at")
                       .order(open_at: :asc, id: :asc)
                       .group_by { |x| x[:open_at].to_date }
                       .sort
    results = []
    target ||= (2..50).map { |x| x * 10 }
    max_threads = 16 # Limite de 8 threads

    batches = target.each_slice(target.size / max_threads).to_a

    semaphore = Mutex.new

    threads = batches.map do |batch|
      Thread.new do
        batch_results = []
        batch.each do |mfe_target|
          target.each do |loss_set|
            result = mfe_analyze(mfe_target, loss_set, grouped_data)
            performance_metric = mfe_calculate_performance_metric(result)
            batch_results << { mfe_target: mfe_target, loss_set: loss_set, performance: performance_metric }
          end
        end
        semaphore.synchronize { results.concat(batch_results) }
      end
    end

    threads.each(&:join)

    
    self.update(mfe_analyzed: results)
    mfe_best_result
  end


  def mfe_calculate_performance_metric(result)
    result.map{|x| x[:profit_date]}.sum
    # Implemente uma lógica para calcular a métrica de desempenho
  end

  def mfe_best_result
    best_result = mfe_analyzed.max_by { |r| r[:performance] } if mfe_analyzed
  end

  private 

  def associated_with_customer_plan_and_amount_greater_than_zero
    if self.customer_plan.nil?
      errors.add(:base, 'Trace must be associated with a CustomerPlan')
    # elsif customer_plans.any? { |cp| cp.amount <= 0 }
    elsif customer_plan.amount_use <= 0 || customer_plan.amount.nil?
      errors.add(:base, 'Associated CustomerPlan must have an amount greater than 0')
    end
  end

end