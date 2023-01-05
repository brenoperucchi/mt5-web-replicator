class CreateCustomerPlans < ActiveRecord::Migration[6.1]
  def change
    create_table :customer_plans do |t|
      t.string :name
      t.decimal :amount, :precision => 10, :scale => 2
      t.belongs_to :store, null: false, foreign_key: true
      t.text :settings

      t.timestamps
    end
  end
end
