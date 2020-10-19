class AddSymbolToOrders < ActiveRecord::Migration[6.0]
  def change
  	add_column :orders, :symbol, :string
  end
end
