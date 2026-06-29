class CreateBalances < ActiveRecord::Migration[6.1]
  def change
    create_table :balances do |t|
      t.belongs_to :account
      t.belongs_to :slave
      t.belongs_to :deal
      t.timestamps
    end
  end
end
