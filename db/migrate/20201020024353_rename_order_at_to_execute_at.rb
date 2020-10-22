class RenameOrderAtToExecuteAt < ActiveRecord::Migration[6.0]
  def change
  	rename_column :orders, :order_at, :execute_at
  end
end
