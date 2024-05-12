class Customer < ApplicationRecord
  # attr_accessor :user_email
  
  CONTROL_ROLE = %w(admin user)

  store :settings, accessors: [:stripe_product_id, :stripe_customer_id]#, :email, :password]

  enum role: {administrator:0, customer:1}
  enum role_control: {owner:0, admin:1, user:2}

  include LibControl
  include LibEnums

  scope :not_deleted, -> { where(deleted_at:nil) }

  # before_update :register_plan_update
  # after_create :register_plan_create

  belongs_to :store
  has_one  :user,        as: :userable, dependent: :destroy
  has_many :plan_usages, as: :resourceable#, dependent: :destroy
  
  has_many :invoices,    as: :invoiceable, dependent: :destroy
  has_many :invoice_items, through: :invoices, source: :items

  has_many :tokens,      as: :tokenable, dependent: :destroy
  
  has_many :accounts,       dependent: :destroy  
  has_many :traces,         through: :accounts, :source => :traces
  
  has_many :plan_customers, dependent: :destroy
  has_many :customer_plans, through: :plan_customers, source: :customer_plan#, dependent: :destroy
  

  delegate :email, to: :user, allow_nil: true

  pay_customer
  accepts_nested_attributes_for :user

  validates_presence_of :name
  validates :role_control, inclusion:["user", "admin"], :if => proc { |obj| obj.customer? && !obj.owner? }
  
  # validates_presence_of [:customer_plan, :role_control], :if => proc { |obj| obj.customer? && obj.owner? }
  # def register_plan_update
  #   if customer_plan_id_changed? or self.plan_usages.empty?
  #     store.register_resource_plan_customer(self, self.class.name.capitalize) if Current.user.try(:userable).try(:role) == "customer"
  #   end
  # end

  # def register_plan_create
  #   plan = CustomerPlan.find_by(id:self.customer_plan_id)
  #   self.plan_usages.create(usageable: plan, resourceable:self, active_at:DateTime.now, handle: "CustomerPlan", store: self.store)
  # end

  def create_invoice(name = nil, date = nil, month_proporcional = false)
    date ||= DateTime.now
    date = date - 1.month

    name = name.blank? ? "#{self.id}-#{date.strftime("%Y-%m")}" : name
    invoice = invoices.find_by(name: name, store:store)
    if invoice.nil?
      invoice = invoices.new(name: name, store:store)
      invoice.customer_calculate(self, date, month_proporcional)
      invoice.balance_update
    end
    invoice&.conciliate_request
    invoice
  end
  
end