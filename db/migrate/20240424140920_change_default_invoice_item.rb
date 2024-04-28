class ChangeDefaultInvoiceItem < ActiveRecord::Migration[6.1]
  def change
    change_column_default :invoice_items, :amount, default:0
  end
end
