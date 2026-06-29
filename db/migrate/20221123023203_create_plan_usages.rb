class CreatePlanUsages < ActiveRecord::Migration[6.1]
  def change
    create_table :plan_usages do |t|
      t.string :description
      t.integer :quantity
      t.references :usageable, null: false, polymorphic: true, index: false
      t.belongs_to :store, null: false, foreign_key: true

      t.datetime :active_at

      t.timestamps
    end
  end
end
