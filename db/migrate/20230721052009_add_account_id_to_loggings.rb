class AddAccountIdToLoggings < ActiveRecord::Migration[6.1]
  def change
    add_reference :loggings, :account
  end
end
