class AddAccountTraceToInvoiceItems < ActiveRecord::Migration[6.1]
  def change
    add_reference :invoice_items, :account
    add_reference :invoice_items, :trace
  end
end
