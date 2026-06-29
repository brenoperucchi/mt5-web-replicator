class AddAccountIdToSlaves < ActiveRecord::Migration[6.0]
  def change
    add_reference :transaction_slaves, :account, foreign_key: true
  end
end
