class AddAccountToUploadFile < ActiveRecord::Migration[6.1]
  def change
    add_reference :upload_files, :account
  end
end
