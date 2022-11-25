class AddStoreIdToPlanItems < ActiveRecord::Migration[6.1]
  def change
    add_reference :plan_items, :store, foreign_key: true, index:true
  end
end
