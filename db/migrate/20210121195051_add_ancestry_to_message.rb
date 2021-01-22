class AddAncestryToMessage < ActiveRecord::Migration[6.0]
  def change
    add_column :message, :ancestry, :string
    add_index :message, :ancestry
  end
end
