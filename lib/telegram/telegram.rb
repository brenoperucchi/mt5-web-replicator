#!/usr/bin/env ruby
require 'rubygems'
# require 'ffi-rzmq'
require File.expand_path('../../../config/environment', __FILE__)
require 'pycall/import'

include PyCall::Import
PyCall.sys.path.append File.dirname(Rails.root.join('lib/telegram', 'telegramf'))
pyfrom 'telegramf', import: :'Telegramf'

def telegram_request_msg
  telegram = Telegramf.new()
  telegram.connect()
  loop do
    sleep(10)
    traces = Store.first.traces.active.telegram
    if traces.present?
      traces.each do |trace|
        t_response = telegram.query_message(trace)
        if t_response['error']
          trace.update_column(:response, t_response['chat_history']) if trace.response != t_response['chat_history']
        else
          t_response['chat_history']['messages'].each do |content|
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
                end
                root_message.prepare
              end
            end
          end
        end
      end
    end
  end
  telegram.disconnect()
end