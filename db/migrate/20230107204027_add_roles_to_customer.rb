class AddRolesToCustomer < ActiveRecord::Migration[6.1]
  def change
    add_column :customers, :role, :integer, default: 0
    add_column :customers, :role_control, :integer, default: 0
  end
end
