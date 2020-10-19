class AddEnvironmentToSlave < ActiveRecord::Migration[6.0]
  def change
  	add_column :slaves, :environment, :string
  end
end
