class AddPriceClosedToTransactionSlaves < ActiveRecord::Migration[6.1]
  def change
    add_column :transaction_slaves, :price_closed, :string
  end
end
