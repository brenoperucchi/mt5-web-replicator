class AddMessageIdToTransactions < ActiveRecord::Migration[6.0]
  def change
    add_reference :transactions, :message, index: true
  end
end
