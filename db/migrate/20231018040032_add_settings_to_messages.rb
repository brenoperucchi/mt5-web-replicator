class AddSettingsToMessages < ActiveRecord::Migration[6.1]
  def change
    add_column :messages, :settings, :text
  end
end
