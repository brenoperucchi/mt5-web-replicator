class AddIndexesToTables < ActiveRecord::Migration[6.1]
  def change
    add_index :loggings, [:account_id, :state, :created_at], name: 'idx_loggings_account_state_created_at'
    add_index :transaction_slaves, :order_id, name: 'idx_transaction_slaves_order_id'
    add_index :orders, :id, name: 'idx_orders_id'
    add_index :balances, :order_id, name: 'idx_balances_order_id'
    add_index :balances, :account_id, name: 'idx_balances_account_id'
    add_index :transaction_slaves, [:state, :closed_at], name: 'idx_transaction_slaves_state_closed_at'
  end
end
