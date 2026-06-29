class AddOrderIdToBalances < ActiveRecord::Migration[6.1]
  def change
    add_reference :balances, :order
  end
end
