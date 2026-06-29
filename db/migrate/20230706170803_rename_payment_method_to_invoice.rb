class RenamePaymentMethodToInvoice < ActiveRecord::Migration[6.1]
  def up
    rename_column :invoices, :payment_method_id, :payment_id
  end

  def down
    rename_column :invoices, :payment_id, :payment_method_id
  end
end
