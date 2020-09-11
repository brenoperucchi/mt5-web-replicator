class AddEnvironmentToSign < ActiveRecord::Migration[6.0]
  def change
  	add_column :signs, :environment, :string
  end
end
