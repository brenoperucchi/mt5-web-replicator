class AddPaymentIdToCustomerPlans < ActiveRecord::Migration[6.1]
  def change
    add_reference :customer_plans, :payment
  end
end
