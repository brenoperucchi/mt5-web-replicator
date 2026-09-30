# Experimental Telegram bot helpers. Everything here is a no-op unless
# ENABLE_TELEGRAM=1 (Rails.configuration.x.telegram_enabled); the
# telegram-bot-ruby gem is only required when the flag is on.
module BotTelegram
  def self.enabled?
    Rails.configuration.x.telegram_enabled
  end

  def telegram_token
    ENV["TELEGRAM_BOT_TOKEN"].presence || Rails.application.credentials[:telegram_token]
  end

  def telegram_client_run(&block)
    return unless BotTelegram.enabled? && !Rails.env.test?

    require 'telegram/bot'
    Telegram::Bot::Client.run(telegram_token, &block)
  end

  def check_chat_id(chat_id, bot)
    bot.api.get_chat(chat_id: chat_id)
    true
  rescue StandardError
    false
  end

  def channel_id(title)
    telegram_client_run do |bot|
      bot.fetch_channel.each do |channel|
        return channel.chat.title.include?(title) ? channel.chat : false
      end
    end
  end

  def set_webhook(url, token = nil)
    telegram_client_run do |bot|
      bot.api.set_webhook(url: url, secret_token: token.to_s)
    end
  end

  def listen
    telegram_client_run do |bot|
      bot.listen do |message|
        case message.text
        when '/start'
          bot.api.send_message(chat_id: message.chat.id, text: "Hello, #{message.from.first_name}")
        when '/stop'
          bot.api.send_message(chat_id: message.chat.id, text: "Bye, #{message.from.first_name}")
        end
      end
    end
  end

  def telegram_send_message(chat_id, message)
    telegram_client_run do |bot|
      if check_chat_id(chat_id, bot)
        begin
          bot.api.send_message(chat_id: chat_id, text: message)
        rescue StandardError
          true
        end
      end
    end
  end
end
