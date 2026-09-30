class TelegramJob
  include Sidekiq::Worker
  include Telegram::Util
  include BotTelegram

  def perform(chat_id, content)
    return unless BotTelegram.enabled?

    telegram_send_message(chat_id, content)
  end
end