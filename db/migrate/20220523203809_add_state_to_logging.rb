class AddStateToLogging < ActiveRecord::Migration[6.1]
  def change
    add_column :loggings, :state, :string
  end
end
