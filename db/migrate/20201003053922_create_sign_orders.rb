class CreateSignOrders < ActiveRecord::Migration[6.0]
  def change
    create_table :sign_orders do |t|
      t.string :message
      t.integer :message_id, index: true
      t.datetime :active_at, :ready_at, :order_at

      t.references :sign_trace, null: false, index: true

      t.timestamps
    end
  end
end
