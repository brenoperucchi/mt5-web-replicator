class CreateInvoiceItems < ActiveRecord::Migration[6.1]
  def change
    create_table :invoice_items do |t|
      t.string :name
      t.text :settings
      t.decimal :amount, :precision => 10, :scale => 2
      t.references :invoice, null: false, foreign_key: true

      t.timestamps
    end
  end
end
