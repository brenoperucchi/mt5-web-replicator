class RemoveUserIdToCustomers < ActiveRecord::Migration[6.1]
  def change
    remove_column :customers, :user_id, :integer
  end
end
