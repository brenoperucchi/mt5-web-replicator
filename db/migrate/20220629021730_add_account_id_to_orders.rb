class AddAccountIdToOrders < ActiveRecord::Migration[6.1]
  def change
    add_reference :orders, :account
  end
end
