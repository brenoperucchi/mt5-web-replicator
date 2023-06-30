class AddUniqueIndexContentIdToOrders < ActiveRecord::Migration[6.1]
  def change
    add_index :orders, :content_id
  end
end
