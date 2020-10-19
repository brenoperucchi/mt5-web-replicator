class AddSettingsToTrace < ActiveRecord::Migration[6.0]
  def change
    add_column :traces, :settings, :text
  end
end
