class RemoveForeignKey < ActiveRecord::Migration[6.1]
  def change
    if foreign_key_exists?(:transactions, :accounts)
      remove_foreign_key :transactions, :accounts
    end
    if foreign_key_exists?(:transaction_slaves, :accounts)
      remove_foreign_key :transaction_slaves, :accounts
    end
  end
end
