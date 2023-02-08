class RemoveForeignKeyToTransactions < ActiveRecord::Migration[6.1]
  def down
    remove_foreign_key :transactions, name: :fk_rails_934b94f769
  end
  def up
  end
end
