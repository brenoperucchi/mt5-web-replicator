class AddClosedAtToTransactions < ActiveRecord::Migration[6.1]
  def change
    add_column :transactions, :closed_at, :datetime
  end
end
