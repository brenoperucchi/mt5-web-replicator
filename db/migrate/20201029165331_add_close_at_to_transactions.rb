class AddCloseAtToTransactions < ActiveRecord::Migration[6.0]
  def change
  	add_column :transactions, :close_at, :datetime
  end
end
