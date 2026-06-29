class AddFieldsToTransactionAndSlaves < ActiveRecord::Migration[6.1]
  def change
    add_column :transactions,       :entry, :integer
    add_column :transaction_slaves, :entry, :integer
    add_column :transactions,       :position_id, :bigint
    add_column :transaction_slaves, :position_id, :bigint
  end
end
