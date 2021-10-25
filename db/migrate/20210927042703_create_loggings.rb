class CreateLoggings < ActiveRecord::Migration[6.0]
  def change
    create_table :loggings do |t|
      t.string :content
      t.belongs_to :user
      t.belongs_to :loggerable, polymorphic: true

      t.timestamps
    end
  end
end
