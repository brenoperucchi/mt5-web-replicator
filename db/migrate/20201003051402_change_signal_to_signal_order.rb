class ChangeSignalToSignalOrder < ActiveRecord::Migration[6.0]
  def change
  	  rename_table :signs, :sign_slaves
  end
end
