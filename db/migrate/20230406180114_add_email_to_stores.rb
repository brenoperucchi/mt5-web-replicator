class AddEmailToStores < ActiveRecord::Migration[6.1]
  def change
    add_column :stores, :email, :string
  end
end
