class RemoveConstraintInvoiceIdToInvoiceItems < ActiveRecord::Migration[6.1]
  def change
    remove_foreign_key :invoice_items, name: :fk_rails_25bf3d2c5e
  end
end
