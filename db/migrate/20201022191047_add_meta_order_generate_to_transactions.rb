class AddMetaOrderGenerateToTransactions < ActiveRecord::Migration[6.0]
  def change
  	add_column :transactions, :meta_order_generate, :string
  end
end
