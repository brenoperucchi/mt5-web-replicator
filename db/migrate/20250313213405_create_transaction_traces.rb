class CreateTransactionTraces < ActiveRecord::Migration[6.1]
  def change
    create_table :transaction_traces do |t|
      t.references :master, null: false
      t.references :trace, null: false

      t.timestamps
    end
  end
end
