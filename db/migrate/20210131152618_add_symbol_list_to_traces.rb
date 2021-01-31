class AddSymbolListToTraces < ActiveRecord::Migration[6.0]
  def change
    add_column :traces, :symbol_list, :text
  end
end