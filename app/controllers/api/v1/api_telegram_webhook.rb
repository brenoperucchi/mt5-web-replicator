require 'csv'
require 'json'
module API
  module V1
    class APITelegramWebhook < Grape::API
      include API::V1::Defaults

      resource :telegram do
        desc "Receive Telegram Message"
        post "/webhook/" do
          Rails.logger.info "API call: #{headers}\tWith params: #{params.inspect}"

          telegram_response    = params.to_o
          
          chat_id     = telegram_response.try(:my_chat_member).try(:chat).try(:id)
          chat_title  = telegram_response.try(:my_chat_member).try(:chat).try(:title)

          message_chat_id = telegram_response.try(:message).try(:chat).try(:id)
          message_chat_text = telegram_response.try(:message).try(:text)
          status = telegram_response.try(:my_chat_member).try(:new_chat_member).try(:status)
          
          chat_id ||= message_chat_id
          store = Store.find_by(telegram_bot_chat_id: chat_id) unless chat_id.nil?

          if message_chat_text.present?
            case message_chat_text
            when "/start"
              BotTelegram.send_message(store.telegram_bot_chat_id, "Iniciando o log das operações")
            when "/stop"
              BotTelegram.send_message(store.telegram_bot_chat_id, "Finalizando o log das operações")
            else
              BotTelegram.send_message(store.telegram_bot_chat_id, "Ainda estou apreendendo sobre isso")
            end
          elsif store and status == "left"
            store.telegram_bot_status = status
            store.telegram_bot_chat_id = nil
            store.save if store.changes.present?
          elsif not chat_title.nil?
            Store.all.each do |store| 
              # binding.pry
              status = telegram_response.my_chat_member.try(:new_chat_member).try(:status)
              next unless store.telegram_bot_chat_name.present?
              if chat_title.include?(store.telegram_bot_chat_name.to_s)
                store.telegram_bot_chat_id = chat_id
                store.telegram_bot_status = status
                store.save if store.changes.present?
              end
            end
          end          
          status 200
        end   
      end

    end
  end
end