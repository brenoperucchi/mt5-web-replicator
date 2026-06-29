class CreateOrderTransactions < ActiveRecord::Migration[6.1]
  def change
    create_table :order_transactions do |t|
      t.references :order, null: false, foreign_key: true
      t.references :transaction, null: false, foreign_key: true

      t.timestamps
    end
  end
end
