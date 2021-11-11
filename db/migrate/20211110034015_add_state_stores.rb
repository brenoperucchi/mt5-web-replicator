class AddStateStores < ActiveRecord::Migration[6.0]
  def change
    add_column :stores, :state, :integer, default:0
  end
end
