class AddDescriptionToInvoiceItens < ActiveRecord::Migration[6.1]
  def change
    add_column :invoice_items, :description, :text
  end
end
