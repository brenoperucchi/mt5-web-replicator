class CreateOrders < ActiveRecord::Migration[6.0]
  def change
    create_table :orders do |t|
      t.string :state, :response
      t.string :content, :content_id
      t.datetime :active_at, :ready_at, :order_at

      t.references :trace, null: false, index: true

      t.timestamps
    end
  end
end
