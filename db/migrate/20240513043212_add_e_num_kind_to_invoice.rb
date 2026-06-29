class AddENumKindToInvoice < ActiveRecord::Migration[6.1]
  def change
    add_column :invoices, :kind, :integer, default:0
  end
end
