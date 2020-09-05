class CreateSigns < ActiveRecord::Migration[6.0]
  def change
    create_table :signs do |t|
      t.string :provider
      t.string :provider_name
      t.string :action
      t.string :kind
      t.string :symbol
      t.string :price_request
      t.string :price_open
      t.string :stop_loss
      t.string :take_profit_1
      t.string :take_profit_2
      t.string :comment
      t.string :lots
      t.string :magic
      t.string :ticket
      t.text :context
      t.datetime :open_at
      t.string :response
      t.string :response_value

      t.timestamps
    end
  end
end
  