class CreateTransactions < ActiveRecord::Migration[6.0]
  def change
    create_table :transactions do |t|
      t.string :state
      t.string :ticket
      t.decimal :profit
      t.belongs_to :order#, null: false, foreign_key: true

      t.string :ordertype
      t.string :symbol
      t.string :price_request
      t.string :price_open
      t.string :stop_loss
      t.string :take_profit
      t.string :comment
      t.string :lot
      t.string :magic_number
      # t.text :context
      t.string :response
      t.string :response_error
      t.datetime :open_at


      t.timestamps
    end
  end
end
