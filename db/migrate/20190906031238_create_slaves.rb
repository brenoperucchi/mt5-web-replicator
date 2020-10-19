class CreateSlaves < ActiveRecord::Migration[6.0]
  def change
    create_table :slaves do |t|
      t.references :trace, null: false, index: true
      # t.string :provider
      # t.string :provider_name
      # t.string :action
      # t.string :kind
      # t.string :symbol
      # t.string :price_request
      # t.string :price_open
      # t.string :stop_loss
      # t.string :take_profit_1
      # t.string :take_profit_2
      # t.string :comment
      # t.string :lots
      # t.string :magic
      # t.string :ticket
      # t.text :context
      # t.string :response
      # t.string :response_value
      # t.datetime :open_at

      t.timestamps
    end
  end
end
  