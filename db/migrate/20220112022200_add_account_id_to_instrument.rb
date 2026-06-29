class AddAccountIdToInstrument < ActiveRecord::Migration[6.0]
  def change
    add_reference :instruments, :account, foreign_key: true
  end
end
