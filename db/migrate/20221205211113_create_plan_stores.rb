class CreatePlanStores < ActiveRecord::Migration[6.1]
  def change
    create_table :plan_stores do |t|
      t.belongs_to :store, null: false, foreign_key: true, index: true
      t.belongs_to :plan_item, null: false, foreign_key: true, index: true

      t.timestamps
    end
  end
end
