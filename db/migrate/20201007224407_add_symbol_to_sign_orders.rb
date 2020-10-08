class AddSymbolToSignOrders < ActiveRecord::Migration[6.0]
  def change
  	add_column :sign_orders, :symbol, :string
  end
end
