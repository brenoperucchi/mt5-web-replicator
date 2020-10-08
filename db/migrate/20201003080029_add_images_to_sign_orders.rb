class AddImagesToSignOrders < ActiveRecord::Migration[6.0]
  def change
		add_column :sign_orders, :image, :string
  end
end
