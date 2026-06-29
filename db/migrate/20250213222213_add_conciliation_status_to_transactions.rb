class AddConciliationStatusToTransactions < ActiveRecord::Migration[6.1]
  def up
    add_column :transactions, :conciliated_at, :datetime
    add_column :transaction_slaves, :conciliated_at, :datetime
    add_column :orders, :conciliated_at, :datetime
  end
  def down
    remove_column :transactions, :conciliated_at, :datetime
    remove_column :transaction_slaves, :conciliated_at, :datetime
    remove_column :orders, :conciliated_at, :datetime
  end
end