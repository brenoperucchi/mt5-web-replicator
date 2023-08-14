class RemoveCloseAtTransactions < ActiveRecord::Migration[6.1]
  def change
    remove_column :transactions, :close_at, :datetime
  end
end
