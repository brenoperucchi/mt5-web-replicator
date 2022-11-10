require 'telegram/bot'

class TelegramJob
  include Sidekiq::Worker
  include Telegram::Util
  include BotTelegram

  def perform(chat_id, content)
    telegram_send_message(chat_id, content)
  end
end