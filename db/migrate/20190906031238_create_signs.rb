class CreateSigns < ActiveRecord::Migration[6.0]
  def change
    create_table :signs do |t|
      t.string :currency
      t.decimal :take_profit2
      t.decimal :take_profit1
      t.decimal :stop_loss
      t.decimal :price
      t.string :kind
      t.string :broker
      t.string :social
      t.datetime :order_at

      t.timestamps
    end
  end
end
  