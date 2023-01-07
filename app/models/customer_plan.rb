class CustomerPlan < ApplicationRecord
  belongs_to :store, optional:true
  has_many :customers
  has_many :plan_usages, as: :usageable

  validates_presence_of [:name, :amount], :on => :create, :if => proc { |obj| Current.user.userable.role == "customer" }

  accepts_nested_attributes_for :customers
end
