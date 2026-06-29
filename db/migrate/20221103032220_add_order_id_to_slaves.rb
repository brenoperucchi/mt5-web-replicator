class AddOrderIdToSlaves < ActiveRecord::Migration[6.1]
  def change
    add_column :transaction_slaves,       :order_id, :integer, index:true
  end
end
