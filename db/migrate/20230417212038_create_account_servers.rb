class CreateAccountServers < ActiveRecord::Migration[6.1]
  def change
    create_table :account_servers do |t|
      t.string :name
      # t.string :account_name_id
      # t.references :account

      t.timestamps
    end
  end
end
