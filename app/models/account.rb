require 'lib_enums'
class Account < ApplicationRecord
  attr_accessor :search_date_begin, :search_date_end, :search_magic_number

  # include Balance::Base
  include LibEnums
  include LibControl
  include AlgoStatistic
  
  # after_create :register_resource_plan
  # after_save :insert_instruments
  after_create :set_settings

  # default_scope { where(deleted_at: nil) }

  scope :deleted,       -> { where.not(deleted_at:nil) }
  scope :not_deleted,   -> { where(deleted_at:nil) }
  scope :control_store, ->(store) { where(store: store )}

  enum state:            {disable: 0, enable: 1}
  enum kind:             {slave: 0,   copy: 1}
  enum meta_mode:        {demo: 0,    real: 1}
  enum meta_margin_mode: {netting: 0, hedging: 1}
  enum stock_kind:       {b3: 0,      forex: 1, usa:2, others:4}

  store :settings, accessors: [:magics_accept, :instrument_control, :contract_volume, :api_debug_mode, :api_freeze_max_time, :api_time_to_check_server, 
                               :api_time_max_seconds, :api_slippage, :api_environment_local, :api_store_state, :api_store_message, :api_milliseconds_timer, :api_milliseconds_tick, 
                               :api_event_on_timer, :api_event_on_tick, :api_debug_mode_level, :api_mfe_mae_display, :api_reach_mfe_target, :api_reach_loss_set, 
                               :api_send_orders_history, :api_close_all_orders, :api_milliseconds_delay, :api_orders_to_conciliate]
  belongs_to :store
  belongs_to :customer
  belongs_to :account_server, optional: true

  has_many :invoices, through: :customer, source: :invoices
  has_many :invoice_items, through: :customer, source: :invoice_items

  has_many :plan_usages, as: :resourceable, dependent: :destroy

  has_many :permissions,    dependent: :destroy
  has_many :traces,         through: :permissions, source: :trace 
  has_many :customer_plans, through: :permissions, source: :customer_plan

  has_many :loggings,     dependent: :destroy
  has_many :upload_files, dependent: :destroy
  has_many :instruments,  dependent: :destroy

  has_many :balances,     dependent: :destroy, autosave: true
  has_many :orders,       through: :balances, source: :order,         dependent: :destroy, autosave: true
  has_many :transactions,-> { distinct }, through: :orders,   source: :transactions,  dependent: :destroy
  has_many :slaves,       ->(account) { where("transaction_slaves.account_id = ?", account.id).distinct },
                           through: :orders, source: :slaves,         dependent: :destroy

  has_many :masters,      class_name: 'Transaction',  dependent: :destroy
  has_many :transaction_slaves, dependent: :destroy

  validates_presence_of :name
  validates :name, format: { with: /\A\d+\z/} #, message: "Integer only. No sign allowed." }
  validates_uniqueness_of :name, scope: [:store_id, :account_server_id, :kind], if: Proc.new { |b| b.store_id.present? }
  # validates_uniqueness_of :name, scope: :store_id, if: Proc.new { |b| b.account_server_id.present? }

  accepts_nested_attributes_for :customer
  
  # def register_resource_plan
  #   store.register_resource_plan(self, self.kind)
  # end

  def set_settings
    self.update(self.class.default_settings)
  end

  def self.default_settings
    { api_debug_mode: false, api_debug_mode_level: 1, api_freeze_max_time: 30, api_time_to_check_server: 30, api_time_max_seconds: 30, api_slippage: 30, 
      api_environment_local: false, api_store_state: true, api_milliseconds_timer: 2400, api_milliseconds_tick: 2400, api_event_on_timer: true, 
      api_event_on_tick: false, api_mfe_mae_display: true,  api_send_orders_history: false, api_close_all_orders: false, api_milliseconds_delay: 550, 
      api_orders_to_conciliate: 10
    }
  end

  def contract_volume
    self.settings[:contract_volume].present? ? self.settings[:contract_volume] : "0"
  end


  def register_plan_update
    # if self.trace_ids.include?()
    # if tr_changed? or self.plan_usages.empty?
      # store.register_resource_plan_customer(self, self.class.name.capitalize) if Current.user.try(:userable).try(:role) == "customer"
    # end
  end

  # def register_plan_create
  #   plan = CustomerPlan.find_by(id:self.customer_plan_id)
  #   self.plan_usages.create(usageable: plan, resourceable:self, active_at:DateTime.current, handle: "CustomerPlan", store: self.store)
  # end

  def create_invoice(trace, month_proporcional = false, month=nil)
    date_today = month.nil? ? DateTime.current.beginning_of_month : (DateTime.current + eval("#{month}.month")).beginning_of_month
    name = name.blank? ? "#{self.customer.id}-#{date_today.strftime("%Y-%m")}" : name 

    invoice = customer.invoices.find_or_initialize_by(name: name, store:store, kind: :client)
    invoice.account_calculate(self, trace, date_today, month_proporcional)
    invoice.balance_update
    invoice.conciliate_request
  end

  def add_account_trace_to_planusage(trace, customer_plan)
    plan_usage = customer_plan.plan_usages.where(handle: "AccountTracePlan", resourceable: self, disable_at: nil).take
    permission = Permission.where(trace: trace, customer_plan: customer_plan).last

    plan = permission.customer_plan || store.customer_plans.first
    plan.customers << customer unless plan.customers.exists?(customer.id)
    plan.accounts << self unless plan.accounts.exists?(self.id)

    if plan_usage.nil?
      plan_usage = plan.plan_usages.create(usageable: plan, resourceable:self, active_at:DateTime.current, handle: "AccountTracePlan", store: self.store, plan_serializer:plan.attributes, trace: trace)
      unless plan_usage.errors.any?
        permission.update(plan_usage: plan_usage, customer_plan: plan)
      end
    end
    return plan_usage
  end


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

  def amount_trace(trace)
    plan_usage = plan_usages.where(handle: "AccountTracePlan", resourceable: self, disable_at: nil, trace: trace).try(:last)
    data_profit = data_profit(:slaves, trace)
    plan_usage&.amount_calculate(nil, nil, nil, data_profit)
    plan_usage.try(:amount_profit) || 0
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


  def contract_volume_use
    contract_volume ||= (self.try(:contract_volume) == "0" or self.try(:contract_volume).nil?) ? 1 : self.try(:contract_volume).to_f
  end

  # def api_send_orders_history_date_start
  #   @api_send_orders_history_date_start ||= DateTime.parse(self.settings["api_send_orders_history_date_start"] || DateTime.current.beginning_of_month.beginning_of_day.to_s)
  # end

  # def api_send_orders_history_date_end  
  #   @api_send_orders_history_date_end ||= DateTime.parse(self.settings["api_send_orders_history_date_end"] || DateTime.current.end_of_month.end_of_day.to_s)
  # end                             



  def self.settings_change(timer = nil, tick = nil, delay = nil)
    Account.all.each do |account|
      timer ||= account.api_milliseconds_timer
      tick ||= account.api_milliseconds_tick
      delay ||= account.api_milliseconds_delay

      attributes = {api_debug_mode: false, api_debug_mode_level: 1, api_freeze_max_time: 30, api_time_to_check_server: 30, api_time_max_seconds: 30, api_slippage: 30, 
                    api_environment_local: false, api_store_state: account.api_store_state, api_milliseconds_timer: timer, api_milliseconds_tick: tick, api_event_on_timer: true, 
                    api_event_on_tick: true, api_mfe_mae_display: true,  api_send_orders_history: false, api_close_all_orders: false, api_milliseconds_delay: delay
                   }

      account.update(attributes)
    end
  end

  def init_self_obj
    self.search_date_begin = DateTime.parse("2025-03-10T00:00:00-03:00")
    self.search_date_end   = DateTime.parse("2025-03-10T00:00:00-03:00")
  end

  def self.init_self_test
    @trace = Trace.find(47)
    type = :slaves
    @account  = Account.find(134)
    @account.search_date_begin = DateTime.parse("2025-03-10T00:00:00-03:00")
    @account.search_date_end   = DateTime.parse("2025-03-10T00:00:00-03:00")
    @account = @account.data_scope(type, nil, :all, @trace).where.not(ticket_deal:0).order(open_at: 'DESC').order_limit
  end


end