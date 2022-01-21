class AddTypeMessage < ActiveRecord::Migration[6.0]
  def change
    add_column :messages, :type, :string
  end
end
