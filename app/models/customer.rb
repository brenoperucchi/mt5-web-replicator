class Customer < ApplicationRecord

  CONTROL_ROLE = %w(admin user)
  ENUMS = %w(role role_control)

  store :settings, accessors: [:stripe_product_id, :stripe_customer_id]#, :email, :password]

  enum role: {administrator:0, customer:1}
  enum role_control: {owner:0, admin:1, user:2}
  
  include LibControl
  include LibEnums

  scope :not_deleted, -> { where(deleted_at:nil) }

  before_update :register_plan_update
  after_create :register_plan_create
  
  belongs_to :store
  belongs_to :customer_plan, optional: true
  
  has_one  :user, as: :userable
  # has_one :plan_usage, as: :usageable, :dependent => :destroy
  has_many :plan_usages, as: :resourceable
  
  has_many :accounts, dependent: :nullify
  # has_many :customer_plans, dependent: :nullify
  has_many :invoices, as: :invoiceable#, dependent: :destroy

  delegate :email, to: :user, allow_nil: true

  pay_customer
  accepts_nested_attributes_for :user

  validates_presence_of :name
  validates :role_control, inclusion:["user", "admin"], :if => proc { |obj| obj.customer? and not obj.owner? }
  # validates_presence_of [:customer_plan, :role_control], :if => proc { |obj| obj.customer? and obj.owner? }

  def register_plan_update
    if customer_plan_id_changed? or self.plan_usages.empty?
      store.register_resource_plan_customer(self, self.class.name.capitalize) if Current.user.try(:userable).try(:role) == "customer"
    end
  end

  def register_plan_create
    plan = CustomerPlan.find_by(id:self.customer_plan_id)
    self.plan_usages.create(usageable: plan, resourceable:self, active_at:DateTime.now, handle: "CustomerPlan", store: self.store)
  end

  def create_invoice(name = nil)
    name = name.blank? ? "#{self.id}-#{Time.zone.now.strftime("%Y-%m")}" : name 
    invoice = invoices.find_or_create_by(name: name, store:store)
    if customer_plan.try(:fixed?)
      invoice.items.find_or_create_by(name: :customer_monthly_payment, amount: customer_plan.amount)
    else
      amount = self.accounts.slave.sum(&:balance_month)
      amount_total = (amount.to_f * (customer_plan.try(:amount).to_f / 100))
      
      description = "Invoice #{name}\r\n\n"
      self.accounts.slave.map do |account|
        account.slaves.map do |slave|
          description << "Date: #{I18n.l slave.created_at, format: :short} - Ticket #{slave.ticket_slave} - Symbol:#{slave.symbol} - Profit:#{slave.profit}\r\n" if slave.profit != 0
        end
      end

      description << "Slaves closed count: #{self.accounts.slave.sum(&:balance_month_count)}\r\n"
      description << "Amount:#{amount.to_f} * Plan Percent:#{customer_plan.try(:amount).to_f / 100} = #{amount_total}\r\n"
      invoice.items.find_or_create_by(name: :profit_percent,  amount: amount_total, description: description) 
    end

    invoice.balance_update

    # invoices.find_or_create_by(name: name) do |invoice| 
    #   # invoice.amount = amount
    #   invoice.email = email
    # end
  end
end