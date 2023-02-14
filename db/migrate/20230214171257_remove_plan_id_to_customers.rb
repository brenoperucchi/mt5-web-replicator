class RemovePlanIdToCustomers < ActiveRecord::Migration[6.1]
  def up
    remove_column :customers, :plan_id, foreign_key: true
  end

  def down
    add_reference :customers, :plan_id, foreign_key: true
  end
end
