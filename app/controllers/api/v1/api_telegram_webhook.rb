require 'bot_telegram'
require 'csv'
require 'json'
module API
  module V1
    class APITelegramWebhook < Grape::API
      include API::V1::Defaults
      helpers BotTelegram

      resource :telegram do
        desc "Receive Telegram Message"
        post "/webhook/" do
          Rails.logger.info "API call: #{headers}\tWith params: #{params.inspect}"

          telegram_response    = params.to_o
          
          message_text = params.deep_find("text")
          chat_id      = telegram_response.try(:my_chat_member).try(:chat).try(:id)
          chat_id    ||= telegram_response.try(:message).try(:chat).try(:id)
          @store = Store.where("stores.telegram_bot_chat_id IS NOT NULL AND stores.telegram_bot_chat_id = '#{chat_id}'").try(:take) unless chat_id.nil?

          ## Send start Token in Group
          if message_text.present? and (chat_id < 0) and @store.nil?
            if message_text.include?("/start") and message_text.include?("token")
              message_text = message_text.match(/token(.*?$)/m)[0]
              @store = Store.all.detect{|s| s.telegram_bot_token.to_s.include?(message_text) ? s : nil }
              if @store.is_a?(Store) 
                unless @store.telegram_bot_chat_id.present?
                  @store.update(telegram_bot_chat_id: chat_id, telegram_bot_status: :enable)
                  telegram_send_message(@store.telegram_bot_chat_id, "Alfred foi instalado corretamente. A partir de agora todas as operações passam a ser monitoradas")
                else
                  telegram_send_message(@store.telegram_bot_chat_id, "Alfred já está em funcionamento.")
                end
              end
            end
          end
          ## Action store is nil and 
          if @store.nil?
            telegram_send_message(chat_id, "Atenção!\r\n\nAlfred não instalado, para configura-lo você deve enviar a mensagem com o token dentro do seu grupo. O token pode ser visualizado no:\r\n\nAdmin -> Stores -> Show -> Telegram Bot Token\r\n\nPara configura-lo você deve enviar uma mensagem dentro do seu grupo no telegram.\r\n\nExemplo: /start token123456")          
          elsif @store
            if message_text.to_s.include?("/status")
              chat_title = params.deep_find("title")
              telegram_send_message(@store.telegram_bot_chat_id, "Alfred habilitado para o grupo #{chat_title}")
            end
            if message_text.to_s.include?("/orders")
              telegram_send_message(@store.telegram_bot_chat_id, "Estamos Implementando essa função")
            end
          end
          status 200
        end   
      end
    end
  end
end