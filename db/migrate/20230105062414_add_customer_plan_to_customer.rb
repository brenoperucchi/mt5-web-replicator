class AddCustomerPlanToCustomer < ActiveRecord::Migration[6.1]
  def change
    add_reference :customers, :customer_plan, foreign_key: true
  end
end
