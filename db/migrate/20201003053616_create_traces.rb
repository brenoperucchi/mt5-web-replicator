class CreateTraces < ActiveRecord::Migration[6.0]
  def change
    create_table :traces do |t|
      t.string :name
      t.string :name_id
      t.string :response
      t.datetime :active_at

      t.timestamps
    end
  end
end
