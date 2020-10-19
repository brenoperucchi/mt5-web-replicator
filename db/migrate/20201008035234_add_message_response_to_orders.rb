class AddMessageResponseToOrders < ActiveRecord::Migration[6.0]
  def change
  	add_column :orders, :message_response, :string
  end
end
