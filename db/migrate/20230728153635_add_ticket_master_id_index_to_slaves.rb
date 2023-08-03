class AddTicketMasterIdIndexToSlaves < ActiveRecord::Migration[6.1]
  def up
    add_index :transaction_slaves, [:ticket_master, :account_id], unique: true
  end

  def down
    remove_index :transaction_slaves, [:ticket_master, :account_id]
  end
end
