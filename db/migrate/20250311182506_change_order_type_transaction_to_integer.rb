class ChangeOrderTypeTransactionToInteger < ActiveRecord::Migration[6.1]
  def up
    change_column :transactions, :ordertype,  "integer USING CAST(ordertype AS integer)"
  end

  def down
    change_column :transactions, :ordertype, :string
  end
end
