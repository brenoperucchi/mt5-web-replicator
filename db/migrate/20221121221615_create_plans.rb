class CreatePlans < ActiveRecord::Migration[6.1]
  def change
    create_table :plans do |t|
      t.string :name
      t.text :settings
      t.decimal :amount, precision: 10, scale: 2
      t.datetime :active_at

      t.timestamps
    end
  end
end
