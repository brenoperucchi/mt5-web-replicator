class AddSettingsToCustomer < ActiveRecord::Migration[6.1]
  def change
    add_column :customers, :settings, :text
  end
end
