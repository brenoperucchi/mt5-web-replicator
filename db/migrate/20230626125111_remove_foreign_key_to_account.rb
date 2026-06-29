class RemoveForeignKeyToAccount < ActiveRecord::Migration[6.1]
  def change
    remove_foreign_key :accounts, :customers
  end
end
