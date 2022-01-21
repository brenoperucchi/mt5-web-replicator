class AddTraceToTransaction < ActiveRecord::Migration[6.0]
  def change
    add_reference :transactions, :trace, foreign_key: true
  end
end
