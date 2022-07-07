class AddBelongsToFields < ActiveRecord::Migration[6.1]
  def change
    add_column :transactions,       :deal_id, :integer, index:true
    add_column :transaction_slaves, :deal_id, :integer, index:true
  end
end
