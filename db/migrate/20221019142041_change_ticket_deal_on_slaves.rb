class ChangeTicketDealOnSlaves < ActiveRecord::Migration[6.1]
  def up
    change_column :transaction_slaves, :ticket_deal, :string
  end
  def down
    change_column :transaction_slaves, :ticket_deal, :decimal, :default => 0.0
  end
end
