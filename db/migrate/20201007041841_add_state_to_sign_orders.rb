class AddStateToSignOrders < ActiveRecord::Migration[6.0]
  def change
  	add_column :sign_orders, :state, :string
  end
end
