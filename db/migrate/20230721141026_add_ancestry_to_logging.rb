class AddAncestryToLogging < ActiveRecord::Migration[6.1]
  def change
    change_table(:loggings) do |t|
      # postgres
      t.string "ancestry", collation: 'C', null: true
      t.index "ancestry"
    end
  end
end
