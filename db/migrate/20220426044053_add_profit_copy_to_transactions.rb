class AddProfitCopyToTransactions < ActiveRecord::Migration[6.1]
  def change
    add_column :transactions, :profit_copy, :decimal, precision: 10, scale: 2
  end
end
