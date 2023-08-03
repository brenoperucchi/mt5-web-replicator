class AlterContentToMessagesToText < ActiveRecord::Migration[6.1]
  def change
    change_column :messages, :content, :text
  end
end
