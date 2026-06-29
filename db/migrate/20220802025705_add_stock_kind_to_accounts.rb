class AddStockKindToAccounts < ActiveRecord::Migration[6.1]
  def change
    add_column :accounts, :stock_kind, :integer, default: 0
  end
end
