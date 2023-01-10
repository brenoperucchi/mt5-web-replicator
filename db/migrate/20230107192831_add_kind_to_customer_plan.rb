class AddKindToCustomerPlan < ActiveRecord::Migration[6.1]
  def change
    add_column :customer_plans, :kind, :integer, default: 0
  end
end
