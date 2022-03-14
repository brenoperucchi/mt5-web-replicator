class AddLoggingIdToVersions < ActiveRecord::Migration[6.0]
  def change
    add_reference :versions, :logging, foreign_key: true
  end
end
