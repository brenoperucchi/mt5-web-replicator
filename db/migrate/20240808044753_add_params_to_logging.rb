class AddParamsToLogging < ActiveRecord::Migration[6.1]
  def change
    add_column :loggings, :params, :text
  end
end
