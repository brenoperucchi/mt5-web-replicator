class RemoveIndexUniqToTransactionSlave < ActiveRecord::Migration[6.1]
  def up
    remove_index :transaction_slaves, [:ticket_master, :account_id]
    # add_index :transaction_slaves, [:ticket_master, :account_id, :ticket_slave, :order_id], unique: true
  end

  def down
    add_index :transaction_slaves, [:ticket_master, :account_id], unique: true
    # remove_index :transaction_slaves, [:ticket_master, :account_id, :ticket_slave, :order_id], unique: true
  end
end
