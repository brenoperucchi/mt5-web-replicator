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
  
  before_save :register_plan_changes

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

  has_many :plan_items#, dependent: :destroy
  has_many :plan_usages#, dependent: :destroy

  # has_many :plan_items, dependent: :destroy
  # has_many :plans, -> { distinct }, through: :plan_items, source: :plan
  # has_many :plan_lines, -> { distinct }, through: :plan_items, source: :plan_line


  # has_one :plan_store, dependent: :destroy
  # has_one :plan, through: :plan_store, source: :plan, dependent: :destroy
  # has_many :plans,      through: :plan_stores, source: :plan, dependent: :destroy
  # has_many :plan_lines, through: :plans, source: :plan_lines, dependent: :destroy

  validates_presence_of :plan, :on => :create
  validates_presence_of :name

  accepts_nested_attributes_for :customers, :users

  # scope :active, ->{ where.not(active_at:nil)}

  def register_resource_plan(resource, name)
    plan.verify_plan_has_items(self)
    plan_item = plan.plan_items.where(name: name.downcase).take
    klass = resource.class.name.classify.downcase.pluralize
    klass_count = self.send(klass).count
    if self.plan_usages.where(usageable:resource).count < klass_count
      usage_olders = self.plan_usages.where.not(active_at: nil, disable_at:nil).where(resourceable: resource)
      usage_olders.update_all(active_at:nil) if usage_olders.present?
      self.plan_usages.create(usageable:plan_item, resourceable:resource,  active_at: DateTime.now, handle:plan_item.name)
    end
  end

  def email
    users.first.email    
  end

  def register_plan_changes
    if plan_id_changed? or self.plan_usages.empty?
      plan_older = self.plan_usages.where.not(active_at:nil).where(resourceable:self)
      plan_older.update_all(disable_at:DateTime.now) if plan_older.present?
      self.plan_usages.create(usageable: self.plan, resourceable:self, active_at:DateTime.now, handle: "Plan")
    end
  end


  def telegram_bot_token
    if not telegram_bot_status == "enable" and not self.settings[:telegram_bot_token].present? and not telegram_bot_chat_id.present?
      self.update(telegram_bot_token: "token#{SecureRandom.hex(3)}")
    end
    self.settings[:telegram_bot_token]
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

  def calculate_plan_month
    date_today = DateTime.now
    usages = self.plan_usages.where(active_at: date_today.beginning_of_month..date_today.end_of_month, usageable_type:'Plan')
    usages.each do |usage|
      # next if usages.active_at.month <= DateTime.now.month
      usage.calculate_usage
    end

    %w(Trace Copy Slave).each do |item|
      plan_item = self.plan_items.where(name: item, plan:self.plan)
      self.plan_usages.where(handle:item, usageable_type: 'PlanItem').each do |usage|
        usage.calculate_usage
      end
    end
  end

end