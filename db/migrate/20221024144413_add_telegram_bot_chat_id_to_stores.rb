class AddTelegramBotChatIdToStores < ActiveRecord::Migration[6.1]
  def change
    add_column :stores, :telegram_bot_chat_id, :integer
  end
end
