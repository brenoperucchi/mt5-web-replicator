class CreateUploadFiles < ActiveRecord::Migration[6.1]
  def change
    create_table :upload_files do |t|
      t.references :uploadable, polymorphic: true, index: false
      t.string :kind
      t.belongs_to :store
      t.belongs_to :trace

      t.timestamps
    end
  end
end
