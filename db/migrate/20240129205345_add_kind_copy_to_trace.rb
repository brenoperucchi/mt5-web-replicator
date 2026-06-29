class AddKindCopyToTrace < ActiveRecord::Migration[6.1]
  def change
    add_column :traces, :kind_copy, :integer, default:0
  end
end
