class AddPaymentIdToStores < ActiveRecord::Migration[6.1]
  def change
    add_reference :stores, :payment
  end
end
