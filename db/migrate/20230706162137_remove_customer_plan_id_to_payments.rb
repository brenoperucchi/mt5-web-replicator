class RemoveCustomerPlanIdToPayments < ActiveRecord::Migration[6.1]
  def change
    remove_column :payments, :customer_plan_id, :bigint
  end
end
