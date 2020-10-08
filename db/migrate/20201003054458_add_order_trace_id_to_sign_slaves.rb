class AddOrderTraceIdToSignSlaves < ActiveRecord::Migration[6.0]
  def change
  	add_column :sign_slaves, :order_trace_id, :integer, index:true
  end
end
