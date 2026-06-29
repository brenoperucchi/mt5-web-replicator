class AddRenameTransactionSlave < ActiveRecord::Migration[6.0]
  def change
    add_column    :transaction_slaves, :ticket_slave, :string 
    rename_column :transaction_slaves, :ticket,       :ticket_master
  end
end
