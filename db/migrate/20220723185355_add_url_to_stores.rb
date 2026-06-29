class AddUrlToStores < ActiveRecord::Migration[6.1]
  def change
    add_column :stores, :url, :string
  end
end
