class AddStoreIdToOrders < ActiveRecord::Migration[6.1]
  def change
    add_reference :orders, :store
  end
end
