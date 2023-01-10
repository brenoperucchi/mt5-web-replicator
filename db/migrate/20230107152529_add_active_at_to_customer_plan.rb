class AddActiveAtToCustomerPlan < ActiveRecord::Migration[6.1]
  def change
    add_column :customer_plans, :active_at, :datetime
  end
end
