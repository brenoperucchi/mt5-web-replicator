class AddPaymentMethodToInvoices < ActiveRecord::Migration[6.1]
  def change
    add_reference :invoices, :payment_method
  end
end
