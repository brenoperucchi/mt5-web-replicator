class CustomerPlan < ApplicationRecord
  attr_accessor :active
  enum kind: {fixed: 0, percent: 1}#, _scopes:false
  enum charge_recurrence: {monthly: 1, bimester: 2, semester: 6, annual:12}
  ENUM_discount_behavior = %w(none promition_page always)

  store :settings, accessors: [:meta_margin_mode, :meta_mode, :amount_discount, :discount_behavior, :promotion_use]

  belongs_to :store, optional:true
  belongs_to :payment, optional:true
  
  has_many :plan_usages, as: :usageable#, dependent: :destroy

  has_many :plan_customers, dependent: :destroy
  has_many :customers, through: :plan_customers, source: :customer

  has_many :permissions, dependent: :nullify
  has_many :accounts, through: :permissions, source: :account
  has_many :traces, through: :permissions, source: :trace

  validates_presence_of :store, :payment

  # has_one :payment
  # has_one :payment_method, through: :store, source: :payment_method

  # scope :active,  -> { where.not(active_at:nil) }

  validates_presence_of [:name, :amount], :if => proc { |obj| !Current.user.nil? and Current.user.userable.role == "customer" }
  validates_presence_of :active, :if => :validate_active_at

  accepts_nested_attributes_for :customers, :payment

  def validate_active_at
    self.active == false and self.class.active.present? and self.id == self.class.active.try(:first).try(:id)
  end

  def amount_use
    if self.discount_behavior == "always" || (self.discount_behavior == "promition_page" && self.promotion_use) 

      if self.amount_discount.to_s.include?("%")
        self.amount * (self.amount_discount.to_f / 100)
      else
        self.amount - self.amount_discount.to_f
      end
    else
      self.amount.to_f
    end
  end


  def calculate_amount
    plan_usage = plan_usages.find_by(handle: "AccountTracePlan")
    plan_usage.calculate_usage(DateTime.now) unless plan_usage.nil?
    plan_usage.try(:amount) || customer_plan.amount
    
  end

end