class AddCustomerPlanToCustomer < ActiveRecord::Migration[6.1]
  def change
    add_column :customers, :customer_plan_id, :integer
    add_index :customers,  :customer_plan_id
  end
end
