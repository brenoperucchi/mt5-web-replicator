class AddMessageResponseToSignOrders < ActiveRecord::Migration[6.0]
  def change
  	add_column :sign_orders, :message_response, :string
  end
end
