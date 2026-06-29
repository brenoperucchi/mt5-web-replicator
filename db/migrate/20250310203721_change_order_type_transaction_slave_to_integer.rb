class ChangeOrderTypeTransactionSlaveToInteger < ActiveRecord::Migration[6.1]
  def up
    change_column :transaction_slaves, :ordertype,  "integer USING CAST(ordertype AS integer)"
  end

  def down
    change_column :transaction_slaves, :ordertype, :string
  end
end
