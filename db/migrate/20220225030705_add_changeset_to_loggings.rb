class AddChangesetToLoggings < ActiveRecord::Migration[6.0]
  def change
    add_column :loggings, :changeset, :text
    add_column :loggings, :version_id, :integer, index:true
  end
end
