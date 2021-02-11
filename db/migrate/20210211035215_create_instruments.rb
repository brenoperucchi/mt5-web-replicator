class CreateInstruments < ActiveRecord::Migration[6.0]
  def change
    create_table :instruments do |t|
      t.string :symbol
      t.string :name
      t.belongs_to :trace, index: true
      t.string :volumes

      t.timestamps
    end
  end
end
