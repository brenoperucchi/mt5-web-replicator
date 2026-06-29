class AddFeesToTransactions < ActiveRecord::Migration[6.1]
  def change
    add_column :transactions, :fee, :decimal
    add_column :transaction_slaves, :fee, :decimal
  end
end
