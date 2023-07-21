class AddStateCopyToMessages < ActiveRecord::Migration[6.1]
  def change
    add_column :messages, :state_meta, :string
  end
end
