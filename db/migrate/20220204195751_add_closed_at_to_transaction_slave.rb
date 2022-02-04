class AddClosedAtToTransactionSlave < ActiveRecord::Migration[6.0]
  def change
    add_column :transaction_slaves, :closed_at, :datetime
  end
end
