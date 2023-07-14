class CreateTokens < ActiveRecord::Migration[6.1]
  def change
    create_table :tokens do |t|
      t.references :resourceable, polymorphic: true
      t.references :tokenable,    polymorphic: true
      t.string :name
      t.text :settings

      t.timestamps
    end
  end
end
