class AddCustomerPlanToPermissions < ActiveRecord::Migration[6.1]
  def change
    add_reference :permissions, :customer_plan#, null: false, foreign_key: true
  end
end
