class RemoveConstraintTransactions < ActiveRecord::Migration[6.1]
  def change
    remove_foreign_key :transactions, name: :fk_rails_934b94f769
  end
end
