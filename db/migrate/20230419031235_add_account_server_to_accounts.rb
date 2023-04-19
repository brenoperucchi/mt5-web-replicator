class AddAccountServerToAccounts < ActiveRecord::Migration[6.1]
  def change
    add_reference :accounts, :account_server
  end
end
