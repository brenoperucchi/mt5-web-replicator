require 'rubygems' # or use Bundler.setup
require 'pry'
require 'telegram/bot'

token = '1081923146:AAEbG44qF0cgb0jpHMRy1hLYT6p2gMB37wk'

Telegram::Bot::Client.run(token) do |bot|
  bot.listen do |message|
    case message.text
    when '/start'
      bot.api.send_message(chat_id: message.chat.id, text: "Hello, #{message.from.first_name}")
    when '/stop'
      bot.api.send_message(chat_id: message.chat.id, text: "Bye, #{message.from.first_name}")
    end
  end
end