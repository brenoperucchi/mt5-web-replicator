class AddHostAndPortToTraces < ActiveRecord::Migration[6.0]
  def change
  	add_column :traces, :meta_host, :string
  	add_column :traces, :meta_port, :string
  end
end
