class CreateStatistics < ActiveRecord::Migration[6.1]
  def change
    create_table :statistics do |t|
      t.string :name
      t.decimal :amount, default: 0.0
      t.integer :kind, default: 0
      t.references :statisticable, polymorphic: true, index: false

      t.timestamps
    end
  end
end
