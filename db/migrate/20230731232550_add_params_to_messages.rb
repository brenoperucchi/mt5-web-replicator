class AddParamsToMessages < ActiveRecord::Migration[6.1]
  def change
    add_column :messages, :params, :text
  end
end
