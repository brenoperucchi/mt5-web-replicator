require 'lib_enums'
class Store < ApplicationRecord
  ENUMS = %w(state)
  include LibEnums

  attr_reader :resource_system


  store :settings, accessors: [ :telegram_bot_status, :telegram_bot_token,
                                :telegram_api_id, :telegram_api_number, :telegram_api_hash, :volume_default, 
                                :stripe_webhook_secret, :stripe_api_secret, :stripe_product_id, :stripe_customer_id
                              ]
  enum state: {disable:0, enable:1, deleted:2}
  acts_as_taggable_on :tags
  
  before_update :register_plan_update
  after_create :register_plan_create


  belongs_to :plan
  has_many :accounts, :class_name => "Account", :foreign_key => "store_id", dependent: :destroy
  has_many :traces, :class_name => "Trace", :foreign_key => "store_id", dependent: :destroy
  has_many :orders#, :through => :traces, :source => :orders, dependent: :destroy
  has_many :messages, :class_name => "Message", :foreign_key => "store_id"
  has_many :users, dependent: :destroy

  has_many :transactions, :through => :accounts, :source => :transactions, dependent: :destroy
  has_many :customers,    :through => :users, source: :userable, source_type: 'Customer'
  has_many :invoices, as: :invoiceable#, dependent: :destroy
  has_many :instruments,  :through => :accounts, :source => :instruments

  # has_many :plan_items#, dependent: :destroy
  has_many :plan_usages#, dependent: :destroy

  # has_many :plan_items, dependent: :destroy
  # has_many :plans, -> { distinct }, through: :plan_items, source: :plan
  # has_many :plan_lines, -> { distinct }, through: :plan_items, source: :plan_line


  # has_many :plan_stores, dependent: :destroy
  # has_many :plan_items, through: :plan_stores, source: :plan_item, dependent: :destroy
  # has_many :plans,      through: :plan_stores, source: :plan, dependent: :destroy
  # has_many :plan_lines, through: :plans, source: :plan_lines, dependent: :destroy

  validates_presence_of :plan, :on => :create
  validates_presence_of :name

  accepts_nested_attributes_for :customers, :users

  # scope :active, ->{ where.not(active_at:nil)}

  def register_resource_plan(resource, name)
    # plan.verify_plan_has_items(self)
    resource_handle = name.capitalize
    plan_item = plan.plan_items.where(name: resource_handle).take
    klass = resource.class.name.classify.downcase.pluralize
    klass_count = self.send(klass).count
    
    # if self.plan_usages.where(usageable:resource).count < klass_count
    if resource.plan_usage.nil? and not resource.try(:deleted_at)
      usage_olders = self.plan_usages.where.not(active_at: nil, disable_at:nil).where(resourceable: resource)
      usage_olders.update_all(active_at:nil) if usage_olders.present?
      resource.create_plan_usage(usageable:plan_item,  active_at: DateTime.now, handle:resource_handle, store: self)
    end
  end

  def email
    users.first.email    
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

  def create_invoice_month(month=nil)
    date_today = month.nil? ? DateTime.now : DateTime.now + eval(month)
    # date_today = DateTime.now - 1.month
    #date_today = DateTime.now
    #date_today = DateTime.now + 1.month
    invoice_name = "#{self.id}-#{date_today.strftime("%Y-%m")}"
    invoice = self.invoices.find_or_create_by(name: invoice_name, store:self)

    usages = self.plan_usages.where(usageable_type:'Plan')
    usages.each do |usage|
      create_invoice_item(invoice, usage, date_today)
    end

    %w(Trace Copy Slave).each do |item|
      plan_item = plan.plan_items.where(name: item, plan:self.plan)
      self.plan_usages.where(handle:item, usageable_type: 'PlanItem').each do |usage|
        create_invoice_item(invoice, usage, date_today)      
      end
    end
  end

  private
  
  def create_invoice_item(invoice, usage, date_today)
    if usage.disable_at.present?
      return unless usage.active_at.to_date.month <= date_today.month and usage.active_at.to_date.year <= date_today.year
      if usage.disable_at
        return unless usage.disable_at.month >= date_today.month and usage.disable_at.year >= date_today.year 
      end
    end
    if usage.calculate_usage(date_today)
      invoice.items.find_or_create_by(name: "month_#{usage.handle.try(:downcase)}",  amount: usage.amount, description: usage.description) 
      usage.update(charged_at: date_today)
      invoice.balance_update
    end   
  end

end