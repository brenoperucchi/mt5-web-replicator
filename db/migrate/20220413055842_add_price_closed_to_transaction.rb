class AddPriceClosedToTransaction < ActiveRecord::Migration[6.1]
  def change
    add_column :transactions, :price_closed, :string
  end
end
