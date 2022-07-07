class RemoveProfitCopyToTransactions < ActiveRecord::Migration[6.1]
  def change
    remove_column :transactions, :profit_copy, :decimal, precision: 10, scale: 2
  end
end
