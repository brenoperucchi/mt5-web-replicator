class RemoveForeignKeyCustomers < ActiveRecord::Migration[6.1]
  def change
    remove_foreign_key :customers, :customer_plans
  end
end
