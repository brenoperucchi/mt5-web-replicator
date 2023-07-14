class CreatePaymentMethods < ActiveRecord::Migration[6.1]
  def change
    create_table :payment_methods do |t|
      t.string :name
      t.string :handle
      # t.belongs_to :store
      t.timestamps
    end
  end
end
