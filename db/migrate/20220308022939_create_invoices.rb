class CreateInvoices < ActiveRecord::Migration[6.1]
  def change
    create_table :invoices do |t|
      t.string  :name
      t.integer :state, default:0
      t.references :invoiceable, polymorphic: true
      t.decimal :amount
      t.text :settings

      t.timestamps
    end
  end
end
