class AddCustomerIdToAccounts < ActiveRecord::Migration[6.1]
  def change
    add_reference :accounts, :customer, foreign_key: true
  end
end
