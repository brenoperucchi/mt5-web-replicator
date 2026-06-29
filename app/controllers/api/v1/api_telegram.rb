require 'csv'
require 'json'
module API
  module V1
    class APITelegram < Grape::API
      include API::V1::Defaults

      resource :traces do
        desc "Receive Telegram Message"
        post "/telegram/:trace_id" do
          telegram_params = params
          trace = Trace.find_by(id: params[:trace_id])
          return unless trace
          if telegram_params['error']
            trace.update_column(:response, telegram_params['chat_history']) if trace.response != telegram_params['chat_history']
          else
            telegram_params['chat_history']['messages'].each do |content|
              next if content['content']['text'].nil?
              trace.update_column(:response, nil) if trace.response != nil
              if content['reply_to_message_id'].to_b 
                root_id = content['reply_to_message_id']
                reply_id = content['id']
                root_message = trace.messages.where(content_id: root_id).first
                if root_message.present?
                  reply_message = trace.messages.where(content_id: reply_id).first
                  unless reply_message.present?
                    children = root_message.children.create(
                      content: content['content']['text']['text'], 
                      content_id: content['id'],
                      content_at: Time.at(content['date'].to_i),
                      trace: trace,
                      store: trace.store
                      )
                    children.prepare
                  end
                end
              else
                content_id = content['id']
                if content['content'].include?('text') or content['content'].include?('caption')
                  root_message = trace.messages.where(content_id: content_id).first
                  root_message ||= trace.messages.create do |root_message|
                    root_message.content_id = content['id']
                    root_message.content_at = Time.at(content['date'].to_i)
                    root_message.content = content['content'].include?('text') ? content['content']['text']['text'] : content['content']['caption']['text']
                    root_message.store = trace.store
                    root.message.account = content['account_login'] if trace.copy?
                  end
                  root_message.prepare
                end
              end
            end
          end
        end   
      end
    end
  end
end