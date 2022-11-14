require 'telegram/bot'
# require 'pry-byebug'

module 	BotTelegram

	TOKEN = Rails.application.credentials[:telegram_token]

	def check_chat_id(chat_id, bot)
		begin
			bot.api.get_chat(chat_id: chat_id)
			return true
		rescue
			return false
		end
	end


	def channel_id(title)
		unless Rails.env.test?
			Telegram::Bot::Client.run(TOKEN) do |bot|
				bot.fetch_channel.each do |channel|
					if channel.chat.title.include?(title)
						return channel.chat
					else 
						return false
					end
				end
			end
		end
	end

	def set_webhook(url, token=nil)
		unless Rails.env.test?
			Telegram::Bot::Client.run(TOKEN) do |bot|
				webhook = bot.api.set_webhook(url: url, secret_token: token.to_s)
			end
		end
	end

	def listen
		unless Rails.env.test?
			Telegram::Bot::Client.run(TOKEN) do |bot|
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
	end

	def telegram_send_message(chat_id, message)
		unless Rails.env.test?
			Telegram::Bot::Client.run(TOKEN) do |bot|
				if check_chat_id(chat_id, bot)
					begin 
						bot.api.send_message(chat_id: chat_id, text: message) 
					rescue
						true
					end
				end
			end
		end
	end
end