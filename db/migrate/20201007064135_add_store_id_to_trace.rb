class AddStoreIdToTrace < ActiveRecord::Migration[6.0]
  def change
  	add_column :traces, :store_id, :integer, index:true
  end
end
