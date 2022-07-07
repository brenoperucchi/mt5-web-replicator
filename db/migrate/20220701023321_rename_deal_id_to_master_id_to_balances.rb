class RenameDealIdToMasterIdToBalances < ActiveRecord::Migration[6.1]
  def change
    rename_column :balances, :deal_id, :master_id
  end
end
