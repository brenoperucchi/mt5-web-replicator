class AddStoreIdToInvoices < ActiveRecord::Migration[6.1]
  def change
    add_reference :invoices, :store, foreign_key: true, index:true
  end
end
