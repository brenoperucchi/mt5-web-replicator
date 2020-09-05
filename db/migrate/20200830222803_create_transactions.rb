class CreateTransactions < ActiveRecord::Migration[6.0]
  def change
    create_table :transactions do |t|
    	t.references :signal
			t.string :provider
			t.string :provider_name
      t.string :action
      t.string :kind
      t.string :symbol
      t.string :price
      t.string :price_open
      t.string :stop_loss
      t.string :take_profit_1
      t.string :take_profit_2
      t.string :comment
      t.string :lots
      t.string :magic
      t.string :ticket

      t.timestamps
    end
  end
end
