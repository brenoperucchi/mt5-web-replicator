class AddSettingsToLoggings < ActiveRecord::Migration[6.1]
  def change
    add_column :loggings, :settings, :text
  end
end
