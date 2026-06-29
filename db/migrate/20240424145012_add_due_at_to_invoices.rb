class AddDueAtToInvoices < ActiveRecord::Migration[6.1]
  def change
    add_column :invoices, :due_at, :datetime
  end
end
