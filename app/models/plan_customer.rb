class PlanCustomer < ApplicationRecord
  belongs_to :customer
  belongs_to :customer_plan#, dependent: :destroy
end
