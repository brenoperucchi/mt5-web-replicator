class AddSymbolLocalToTransactionSlaves < ActiveRecord::Migration[8.1]
  def change
    add_column :transaction_slaves, :symbol_local, :string
  end
end
