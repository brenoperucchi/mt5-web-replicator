class CreateStoreTraces < ActiveRecord::Migration[6.1]
  def change
    create_table :store_traces do |t|
      t.references :store, null: false, foreign_key: true
      t.references :trace, null: false, foreign_key: true

      t.timestamps
    end
  end
end
