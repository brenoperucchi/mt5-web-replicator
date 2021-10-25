class RenameMetaPortToKind < ActiveRecord::Migration[6.0]
  def change
    rename_column :traces, :meta_port, :kind
  end
end
