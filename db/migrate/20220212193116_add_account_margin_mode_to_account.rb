 class AddAccountMarginModeToAccount < ActiveRecord::Migration[6.0]
  def up
    add_column :accounts, :meta_mode, :integer, default: 0
    rename_column :accounts, :meta_type, :meta_margin_mode
  end

  def down
    remove_column :accounts, :meta_mode, :integer
    rename_column :accounts, :meta_margin_mode, :meta_type
  end
end
