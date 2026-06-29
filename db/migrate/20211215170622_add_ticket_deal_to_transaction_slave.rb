class AddTicketDealToTransactionSlave < ActiveRecord::Migration[6.0]
  def change
    add_column :transaction_slaves, :ticket_deal, :integer
  end
end
