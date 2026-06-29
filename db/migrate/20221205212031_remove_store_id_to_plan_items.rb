class RemoveStoreIdToPlanItems < ActiveRecord::Migration[6.1]
  def change
    remove_column :plan_items, :store_id, :integer
  end
end
