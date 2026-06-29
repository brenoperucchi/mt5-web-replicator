class AddTicketDealToTransaction < ActiveRecord::Migration[6.1]
  def change
    add_column :transactions, :ticket_deal, :integer
  end
end
