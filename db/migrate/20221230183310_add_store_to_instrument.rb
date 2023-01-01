class AddStoreToInstrument < ActiveRecord::Migration[6.1]
  def change
    add_reference :instruments, :store, foreign_key: true, index:true
  end
end
