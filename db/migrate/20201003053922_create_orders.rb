class CreateOrders < ActiveRecord::Migration[6.0]
  def change
    create_table :orders do |t|
      t.string :state, :message, :message_response
      t.string :message_id#, index: true
      t.datetime :active_at, :ready_at, :order_at

      t.references :trace, null: false, index: true

      t.timestamps
    end
  end
end
