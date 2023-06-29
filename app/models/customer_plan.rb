class CustomerPlan < ApplicationRecord
  attr_accessor :active
  enum kind: {fixed: 0, percent: 1}#, _scopes:false
  enum charge_recurrence: {monthly: 1, bimester: 2, semester: 6, annual:12}

  store :settings, accessors: [:meta_margin_mode, :meta_mode]

  belongs_to :store, optional:true
  has_many :plan_usages, as: :usageable#, dependent: :destroy

  has_many :plan_customers, dependent: :destroy
  has_many :customers, through: :plan_customers, source: :customer, dependent: :destroy

  has_many :permissions, dependent: :nullify
  has_many :accounts, through: :permissions, source: :account
  has_many :traces, through: :permissions, source: :trace


  # scope :active,  -> { where.not(active_at:nil) }

  validates_presence_of [:name, :amount], :if => proc { |obj| !Current.user.nil? and Current.user.userable.role == "customer" }
  validates_presence_of :active, :if => :validate_active_at

  accepts_nested_attributes_for :customers

  def validate_active_at
    self.active == false and self.class.active.present? and self.id == self.class.active.try(:first).try(:id)
  end


end