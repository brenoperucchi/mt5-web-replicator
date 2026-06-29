class RemoveStoresForeignKeyCustomers < ActiveRecord::Migration[6.1]
  def change
    remove_foreign_key :customers, :stores
  end
end
