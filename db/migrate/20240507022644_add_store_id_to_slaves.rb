class AddStoreIdToSlaves < ActiveRecord::Migration[6.1]
  def change
    add_reference :transaction_slaves, :store
  end
end
