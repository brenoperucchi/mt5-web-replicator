class CreatePlanItems < ActiveRecord::Migration[6.1]
  def change
    create_table :plan_items do |t|
      t.string :name
      t.boolean :recurrent
      t.decimal :amount, precision: 10, scale: 2
      t.belongs_to :plan,  foreign:true, index:true
      t.belongs_to :store, foreign:true, index:true
      t.text :settings
      t.datetime :active_at

      t.timestamps
    end
  end
end
