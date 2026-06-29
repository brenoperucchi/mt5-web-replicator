class ChangeStateSlave < ActiveRecord::Migration[6.0]
  def change
    remove_column :transaction_slaves, :state, :string
    add_column :transaction_slaves, :state, :integer, default: 0

  end
end
