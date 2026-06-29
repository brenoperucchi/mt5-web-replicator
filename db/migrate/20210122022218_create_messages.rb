class CreateMessages < ActiveRecord::Migration[6.0]
  def change
    create_table :messages do |t|
      t.string :content
      t.string :content_id
      t.string :state
      t.belongs_to :store
      t.belongs_to :trace
      t.string :ancestry, index: true
      t.string :response
      t.datetime :prepare_at
      t.datetime :content_at

      t.timestamps
    end
  end
end
