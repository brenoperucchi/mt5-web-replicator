class AddSettingsToStore < ActiveRecord::Migration[6.0]
  def change
    add_column :stores, :settings, :text
  end
end
