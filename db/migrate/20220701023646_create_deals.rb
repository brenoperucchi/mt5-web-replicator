class CreateDeals < ActiveRecord::Migration[6.1]
  def change
    create_table :deals do |t|
      t.string :state
      t.string :symbol
      t.string :ticket
      t.belongs_to :account
      t.belongs_to :store
      t.belongs_to :trace

      t.timestamps
    end
  end
end
