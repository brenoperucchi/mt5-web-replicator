class AddStripeFieldsToInvoice < ActiveRecord::Migration[6.1]
  def change
    add_column :invoices, :stripe_invoice_id, :string
  end
end
