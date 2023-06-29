class AddChargeRecurrenceToCustomerPlan < ActiveRecord::Migration[6.1]
  def change
    add_column :customer_plans, :charge_recurrence, :integer, default: 1
  end
end
