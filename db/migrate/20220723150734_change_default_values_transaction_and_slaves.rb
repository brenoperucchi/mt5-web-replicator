class ChangeDefaultValuesTransactionAndSlaves < ActiveRecord::Migration[6.1]
  def change
    change_column :transactions, :profit, :decimal, :default => 0.0
    change_column :transaction_slaves, :profit, :decimal, :default => 0.0
  end
end
