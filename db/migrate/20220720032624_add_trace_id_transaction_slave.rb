class AddTraceIdTransactionSlave < ActiveRecord::Migration[6.1]
  def change
    add_column :transaction_slaves, :trace_id, :integer, index:true
  end
end
