class RemoveTypeMessages < ActiveRecord::Migration[6.1]
  def change
    remove_column :messages, :type, :text
  end
end
