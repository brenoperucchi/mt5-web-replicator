class AddStateToInvoiceItem < ActiveRecord::Migration[6.1]
  def change
    add_column :invoice_items, :state, :integer, default:0
  end
end
