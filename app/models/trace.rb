require 'thread' # Importe a biblioteca de semáforos
require 'lib_enums' # Path: lib/lib_enums.rb
require 'algo_statistic' # Path: lib/algo_statistic.rb

class Trace < ApplicationRecord
  attr_accessor :search_date_begin, :search_date_end, :search_magic_number, :store

  include LibEnums
  include AlgoStatistic
  include LibControl

  enum kind:      { telegram: 0, copy: 1, manual:2}
  enum kind_copy: { normal:   0, prop_firm:1 }

  serialize :mfe_analyzed

  store :settings, accessors: [
                                :telegram_option, :telegram_image, :take_profit_limit,
                                :telegram_api_id, :telegram_api_hash, :telegram_api_number,
                                :instrument_control, :restrict_control_instrument, :magics_accept, :desc_contract, :capital_recomendation, :contract_volume_max,
                                :stock_kind, :capital_multiplier, :magic_same, :desc_finish, :dashboard_restrict
                              ]

  has_many :orders
  has_many :transactions
  has_many :statitics, through: :transactions, source: :statistics
  has_many :masters,-> { distinct },   through: :orders, source: :transactions
  has_many :slaves,    through: :orders, source: :slaves

  has_and_belongs_to_many :messages, class_name: "Message::Message"

  has_many :instruments, class_name: "Instrument", foreign_key: "trace_id", dependent: :destroy

  has_many :store_traces, validate: true
  has_many :stores, through: :store_traces, source: :store,  dependent: :destroy
  belongs_to :store, optional: true

  has_many :transaction_traces, dependent: :destroy
  has_many :trace_transactions, through: :transaction_traces, source: :master, dependent: :destroy

  scope :active,   ->{ where.not(active_at:nil)}
  scope :not_deleted,  -> { where(deleted_at:nil) }
  # scope :telegram, ->{ where(kind:'telegram')}

  has_many :permissions#, dependent: :destroy
  has_many :accounts,       through: :permissions#, source: :slave
  has_many :customer_plans, through: :permissions#, source: :slave
  
  has_many :magic_numbers, as: :magicable, dependent: :destroy
  
  has_one :permission#, dependent: :destroy
  has_one :customer_plan,  through: :permission, source: :customer_plan

  # accepts_nested_attributes_for :payment

  # validates_presence_of   [:name, :name_id]
  validates_presence_of   [:contract_volume_max, :customer_plans]
  
  validates :name, uniqueness: { scope: :store_id }
  validates :name_id, uniqueness: { scope: :store_id }, unless: -> { magic_same.to_b } 

  # Custom validation for name + name_id combination per store
  # validate :unique_name_and_name_id_combination_per_store
  
  validates :capital_recomendation, format: { with: /\A\d+([.,]\d{3})*([.,]\d+)?\z/, message: 'must be a number' }, allow_blank: true

  validate  :validate_customer_plan_and_amount_greater_than_zero, on: :update
  validate  :validate_store_id_and_named_id

  after_save :magic_number_commit
  before_save :normalize_name

  # after_create :set_default_settings

  # def set_default_settings
  #   self.settings ||= {}
  #   self.settings['capital_recomendation'] ||= "0"
  # end

  def settings
    super || {}
  end

  def settings=(value)
    super(value || {})
  end



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

  def next_charged
    days = DateTime.current.day > 15 ? 15 : 0
    (DateTime.current + days + CustomerPlan.charge_recurrences[customer_plan.charge_recurrence.to_s].months).beginning_of_month
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
    values
  end

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
  
  def validate_store_id_and_named_id
    # Skip validation if name_id is blank or magic_same is true
    return if name_id.blank? || magic_same.to_b
    
    # Skip validation for new records with no stores yet
    # return if new_record? && store_ids.blank?
    
    # Validate presence of stores
    if store_ids.blank? && store_traces.blank?
      errors.add(:store_traces, "must have at least one store")
      return
    end
    
    # For each store, check if there's another trace with the same name_id
    store_ids.each do |store_id|
      existing_traces = Trace.joins(:store_traces)
                             .where(store_traces: {store_id: store_id})
                             .where(name_id: name_id)
                             .where.not(id: id) # Exclude the current trace
      
      if existing_traces.exists?
        errors.add(:name_id, "must be unique for store ID #{store_id}")
      end
    end
  end
  
  def normalize_name
    unless self.manual?
      self.name = name.to_s.gsub(/[^0-9A-Za-z]/, '') if name.present? 
    end
  end
  
  def magic_number_commit
    magic_numbers_split = TradeHelperService.magic_numbers_split(magics_accept) || []
    magic_numbers_split.each do |number|
      magic_number = magic_numbers.find_or_create_by(name: number, trace:self)
      if magic_number.active_at.nil? and magic_number.disable_at.present?
        magic_number.update(active_at: Time.current, disable_at: nil)
      end
    end
    magic_numbers.each do |magic_number|
      unless magic_numbers_split.include?(magic_number.name.to_s)
        magic_number.update(disable_at: Time.current, active_at: nil)
      end
    end
  end

  def unique_name_and_name_id_combination_per_store
    # Don't validate if key parts are missing
    return if name.blank? || name_id.blank?

    # Get associated store_ids (handle new and existing records)
    current_store_ids = self.store_ids.presence || self.store_traces.map(&:store_id)
    return if current_store_ids.blank? # Cannot validate without stores

    current_store_ids.each do |s_id|
      # Build query to find conflicts for this specific store_id
      query = Trace.joins(:store_traces)
                  .where(name: self.name, name_id: self.name_id, store_traces: { store_id: s_id })

      # Exclude self if updating
      query = query.where.not(id: self.id) if self.persisted?

      # If a conflicting record exists, add the error
      if query.exists?
        errors.add(:base, "Combination of name ('#{name}') and name_id ('#{name_id}') already exists for store ID #{s_id}")
        # Optionally add errors to specific fields:
        # errors.add(:name, "combination with name_id '#{name_id}' already exists for store ID #{s_id}")
        # errors.add(:name_id, "combination with name '#{name}' already exists for store ID #{s_id}")
      end
    end
  end

  def validate_customer_plan_and_amount_greater_than_zero
    if self.customer_plan.nil?
      errors.add(:base, 'Trace must be associated with a CustomerPlan')
    # elsif customer_plans.any? { |cp| cp.amount <= 0 }
    elsif customer_plan.amount_use <= 0 || customer_plan.amount.nil?
      errors.add(:base, 'Associated CustomerPlan must have an amount greater than 0')
    end
  end

end