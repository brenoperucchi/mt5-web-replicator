class ChangeTicketIdToTransactions < ActiveRecord::Migration[6.1]
  def up
    change_column :transactions,      :ticket,        'bigint USING CAST(ticket AS bigint)'
    change_column :transaction_slaves, :ticket_master, 'bigint USING CAST(ticket_master AS bigint)'
  end
  def down
    change_column :transactions,       :ticket, :string
    change_column :transaction_slaves, :ticket_master, :string
  end
end
