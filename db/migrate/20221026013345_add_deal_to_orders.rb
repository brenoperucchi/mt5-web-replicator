class AddDealToOrders < ActiveRecord::Migration[6.1]
  def change
    add_reference :orders, :deal#, null: false, foreign_key: true
  end
end
