class AddSettingsToSignTrace < ActiveRecord::Migration[6.0]
  def change
    add_column :sign_traces, :settings, :text
  end
end
