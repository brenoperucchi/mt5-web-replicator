require 'lib_enums'
class Store < ApplicationRecord
  ENUMS       = %w(state)
  LANGUAGE    = {Português:'pt-BR', English:'en'}
  DATE_FILTER = {'1 month':'1_month', '3 months':'3_months', '6 months':'6_months', '1_year':'1_year', '2_years':'2_years', '3_years':'3 years'}

  # include LibEnums

  attr_reader :resource_system
  attr_accessor :password

  after_initialize :api_setters
  store :settings, accessors: [ :language, :telegram_bot_status, :telegram_bot_token, :dashboard_restrict,
                                :telegram_api_id, :telegram_api_number, :telegram_api_hash, :volume_default, 
                                :stripe_webhook_secret, :stripe_api_secret, :stripe_product_id, :stripe_customer_id, :contact_whatsapp, :dashboard_date_filter, 
                                :api_server_hostname, :api_debug_mode, :api_freeze_max_time, :api_time_to_check_server, :api_time_max_seconds, :api_slippage, 
                                :api_environment_local, :api_store_state, :api_store_message, :api_milliseconds_timer, :api_milliseconds_tick, :api_event_on_timer,
                                :api_event_on_tick, :api_debug_mode_level, :api_mfe_mae_display
                              ]
  enum state: {disable:0, enable:1}
  acts_as_taggable_on :tags
  
  before_update :register_plan_update
  after_create  :register_plan_create

  belongs_to :plan
  belongs_to :payment, optional: true

  has_many :accounts, dependent: :destroy
  has_many :traces,   dependent: :destroy
  has_many :users,    dependent: :destroy
  has_many :orders,   dependent: :destroy 

  has_many :transactions,-> { distinct }, :through => :accounts, :source => :transactions,                dependent: :destroy
  has_many :customers,                    :through => :users, source: :userable, source_type: 'Customer', dependent: :destroy
  
  has_many :messages, :class_name => "Message::Message",                  dependent: :destroy
  has_many :customer_plans,                                               dependent: :destroy
  has_many :instruments,                                                  dependent: :destroy
  
  has_many :invoices, as: :invoiceable,                                   dependent: :destroy
  has_many :invoice_stores, class_name: :Invoice, foreign_key: :store_id, dependent: :destroy

  has_many :plan_usages, dependent: :destroy
  has_many :payments,    dependent: :destroy
  has_many :payment_methods, through: :payments, source: :payment_method

  has_many :loggings,   as: :loggerable,    dependent: :destroy
  has_many :tokens,     as: :resourceable,  dependent: :destroy

  has_many :plan_stores, dependent: :destroy
  has_many :plan_items, through: :plan_stores, source: :plan_item, dependent: :destroy

  validates_presence_of :plan, :on => :create
  validates_presence_of :name, :email, :url
  validates_uniqueness_of :url, :email

  accepts_nested_attributes_for :customers, :users

  def customer_owner_name
    customers.owner.first.name
  end
  
  def customer_plan
    customer_plans.active.try(:first)
  end

  def register_resources_usages(resource, name)
    # plan.verify_plan_has_items(self)
    resource_handle = name.capitalize
    usageable = plan.plan_items.where(name: resource_handle).take
    usageable ||= plan
    klass = resource.class.name.classify.downcase.pluralize
    klass_count = self.send(klass).count
    
    # if self.plan_usages.where(usageable:resource).count < klass_count
    if resource.plan_usages.blank? and not resource.try(:deleted_at)
      usage_olders = self.plan_usages.where.not(active_at: nil, disable_at:nil).where(resourceable: resource)
      usage_olders.update_all(active_at:nil) if usage_olders.present?
      resource.plan_usages.create(usageable:usageable,  active_at: DateTime.now, handle:resource_handle, store: self)
    end
  end

  def register_customer_plan(resource, name)
    if not resource.try(:deleted_at)
      usage_olders = self.plan_usages.where.not(active_at: nil, disable_at:nil).where(resourceable: resource)
      usage_olders.update_all(disable_at:DateTime.now) if usage_olders.present?
      resource.plan_usages.create(usageable:resource.customer_plan,  active_at: DateTime.now, handle:name, store: self)
    end
  end

  # def email
  #   users.first.email    
  # end

  def disable_store
    plan_older = self.plan_usages.where.not(active_at:nil).where(resourceable:self)
    plan_older.update_all(disable_at:DateTime.now) if plan_older.present?
  end

  def register_plan_update
    if plan_id_changed? or self.plan_usages.empty?
      plan_older = self.plan_usages.where.not(active_at:nil).where(resourceable:self)
      plan_older.update_all(disable_at:DateTime.now) if plan_older.present?
      self.plan_usages.create(usageable: self.plan, resourceable:self, active_at:DateTime.now, handle: "Plan")
    end
  end

  def register_plan_create
    plan = Plan.find_by(id:self.plan_id)
    self.plan_usages.create(usageable: plan, resourceable:self, active_at:DateTime.now, handle: "Plan")
  end

  def telegram_bot_token
    if not telegram_bot_status == "enable" and not self.settings[:telegram_bot_token].present? and not telegram_bot_chat_id.present?
      self.update(telegram_bot_token: "token#{SecureRandom.hex(3)}")
    end
    self.settings[:telegram_bot_token]
  end

  def create_customer_invoice
    self.customers.user.each do |customer|
      customer.create_invoice
    end
  end

  def delete_resource
    self.invoices.destroy_all
    PlanUsage.all.update_all(charged_at:nil)
  end

  def resource_system
    amount_month = calculate_plan_month
    portfolio_total = self.traces.count
    account_copy_total = self.accounts.copy.count
    account_slave_total = self.accounts.slave.count
    response = "Your Plan is #{self.plan} with US #{plan_value}\r\n\r\n"
    
    response << "Portfolio: #{portfolio_total} is amount #{portfolio_total * plan_value.to_f}\r\n"
    response << "Master: #{account_copy_total} is amount #{account_copy_total * plan_value.to_f}\r\n"
    response << "Slave: #{account_slave_total} is amount #{account_slave_total * plan_value.to_f}\r\n"
  end

  def create_invoice_month(proporcional=false, month=nil)
    date_today = month.nil? ? DateTime.now.beginning_of_month : (DateTime.now + eval("#{month}.month")).beginning_of_month
    # date_today = DateTime.now - 1.month
    #date_today = DateTime.now
    #date_today = DateTime.now + 1.month
    invoice_name = "#{self.id}-#{date_today.strftime("%Y-%m")}"
    invoice = self.invoices.find_or_create_by(name: invoice_name, store:self, payment: (self.payment || self.payments.first))

    usages = self.plan_usages.where(usageable_type:'Plan', resourceable_type: 'Store')
    usages.each do |usage|
      create_invoice_item(invoice, usage, date_today, usage.usageable.amount_discount, proporcional)
    end

    %w(Trace Copy Slave).each do |item|
      self.plan_usages.where(handle:item).each do |usage|
        if usage.try(:usageable).try(:amount).nil? or usage.try(:usageable).try(:amount) == 0
          amount = usage.usageable.plan.amount_extra
        else
          amount = usage.usageable.amount
        end
        create_invoice_item(invoice, usage, date_today, amount, proporcional)      
      end
    end
  end

  def self.customer_plan_trace_fixing
    Store.all.each do |store|
      attributes = {name: 'Fist Plan', amount: 100, kind:"fixed", charge_recurrence: "monthly", meta_margin_mode: "hedging", meta_mode: 'demo'}
      if store.customer_plans.empty?
        customer_plan = store.customer_plans.create(attributes)
      else
        customer_plan = store.customer_plans.first
        customer_plan.attributes = attributes
        customer_plan.save
      end
      customer_plan.trace_ids = store.traces.ids
      customer_plan.save
    end
  end

  def self.domain_url
    if Rails.env.production?
      "www.imentore.com.br"
    else
      "signallocal.imentore.com.br:8443"
    end
  end
  
  private
  
  def create_invoice_item(invoice, usage, date_today, amount=nil, proporcional)
    if usage.disable_at.present?
      return unless usage.active_at.to_date.month <= date_today.month and usage.active_at.to_date.year <= date_today.year
      if usage.disable_at
        return unless usage.disable_at.month >= date_today.month and usage.disable_at.year >= date_today.year 
      end
    end
    if usage.calculate_usage(date_today, amount, proporcional)
      item = invoice.items.find_or_create_by(name: "month_#{usage.handle.try(:downcase)}",  amount: usage.amount, description: usage.description) 
      usage.update(charged_at: date_today)
      invoice.balance_update
    end   
  end


  def api_setters
    return if self.id != 1
    methods = {
      api_debug_mode: false, # Valor padrão: false
      api_debug_mode_level: 1, # Valor padrão: 1
      api_freeze_max_time: 16, # Valor padrão: 12
      api_time_to_check_server: 30, # Valor padrão: 30
      api_time_max_seconds: 30, # Valor padrão: 30
      api_slippage: 30, # Valor padrão: 30
      api_environment_local: true, # Valor padrão: false
      api_store_state: true, # Valor padrão: true
      api_store_message: nil, # Valor padrão: nil
      api_milliseconds_timer: 2500, # Valor padrão: 3000
      api_milliseconds_tick: 2000, # Valor padrão: 3000
      api_event_on_timer: true, # Valor padrão: true
      api_event_on_tick: true, # Valor padrão: false
      api_mfe_mae_display: true, # Valor padrão: true
    }
    methods.each do |key, value|
      if self.settings[key.to_s].blank?
        instance_variable_set("@#{key}", value)
        define_singleton_method(key){value}
      end
    end
  end


end