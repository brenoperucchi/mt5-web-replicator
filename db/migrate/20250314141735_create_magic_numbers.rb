class CreateMagicNumbers < ActiveRecord::Migration[6.1]
  def change
    create_table :magic_numbers do |t|
      t.string :name
      t.belongs_to :magicable, polymorphic: true
      t.belongs_to :trace, null: false
      t.belongs_to :store
      t.datetime :active_at
      t.datetime :disable_at

      t.timestamps
    end
  end
end
