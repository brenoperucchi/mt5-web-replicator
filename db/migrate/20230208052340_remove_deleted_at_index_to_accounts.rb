class RemoveDeletedAtIndexToAccounts < ActiveRecord::Migration[6.1]
  def change
    remove_index  :accounts, :deleted_at
  end
end
