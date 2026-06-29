class AddMfeAnalyzedToTraces < ActiveRecord::Migration[6.1]
  def change
    add_column :traces, :mfe_analyzed, :text
  end
end
