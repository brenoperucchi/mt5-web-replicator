class AddStoreIdToSignTrace < ActiveRecord::Migration[6.0]
  def change
  	add_column :sign_traces, :store_id, :integer, index:true
  end
end
