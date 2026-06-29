class AddResponseToInvoices < ActiveRecord::Migration[6.1]
  def change
    add_column :invoices, :response, :text
  end
end
