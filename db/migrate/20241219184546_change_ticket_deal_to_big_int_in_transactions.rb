class ChangeTicketDealToBigIntInTransactions < ActiveRecord::Migration[6.1]
  def up
    change_column :transactions, :ticket_deal, :bigint
  end

  def down
    change_column :transactions, :ticket_deal, :integer
  end
end
