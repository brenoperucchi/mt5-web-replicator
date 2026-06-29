class AlterKindTrace < ActiveRecord::Migration[6.0]
  def up
    remove_column :traces, :kind, :string
    add_column :traces, :kind, :integer, default: 0
  end

  def down
    add_column :traces, :kind, :string, default: 'telegram'
    remove_column :traces, :kind, :integer, default: 0
  end

end
