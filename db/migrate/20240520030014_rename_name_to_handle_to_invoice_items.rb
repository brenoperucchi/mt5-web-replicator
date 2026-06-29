class RenameNameToHandleToInvoiceItems < ActiveRecord::Migration[6.1]
  def change
    rename_column :invoice_items, :name, :handle
  end
end
