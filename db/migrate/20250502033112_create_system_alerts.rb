class CreateSystemAlerts < ActiveRecord::Migration[6.1]
  def change
    create_table :system_alerts do |t|
      t.text :message
      t.string :severity
      t.string :source
      t.integer :source_id
      t.references :alertable, polymorphic: true, index: true
      t.string :status
      t.datetime :resolved_at
      t.jsonb :details

      t.timestamps
    end
  end
end
