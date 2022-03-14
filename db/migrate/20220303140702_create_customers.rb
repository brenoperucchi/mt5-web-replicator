class CreateCustomers < ActiveRecord::Migration[6.0]
  def change
    create_table :customers do |t|
      t.string :name
      t.references :user, null: false, foreign_key: true
      t.datetime :active_at

      t.timestamps
    end
  end
end
