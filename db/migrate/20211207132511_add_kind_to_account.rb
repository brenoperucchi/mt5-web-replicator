class AddKindToAccount < ActiveRecord::Migration[6.0]
  def change
    add_column :accounts, :kind, :integer, default: 0
  end
end
