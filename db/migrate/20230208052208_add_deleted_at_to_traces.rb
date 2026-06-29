class AddDeletedAtToTraces < ActiveRecord::Migration[6.1]
  def change
    add_column :traces, :deleted_at, :datetime
  end
end
