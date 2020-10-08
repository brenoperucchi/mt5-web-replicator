class CreateSignTraces < ActiveRecord::Migration[6.0]
  def change
    create_table :sign_traces do |t|
      t.string :name
      t.string :name_id
      t.datetime :active_at

      t.timestamps
    end
  end
end
