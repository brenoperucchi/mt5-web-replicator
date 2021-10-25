#!/usr/bin/env ruby
require 'rubygems'
require 'ffi-rzmq'
require File.expand_path('../../../config/environment', __FILE__)
require "#{Rails.root}/lib/meta_zmq"
require 'pycall/import'
# require 'meta_api'

# PyCall.import_module('connector')


# require "pathname"
# ENV["RAILS_ENV"] ||= ENV["RACK_ENV"] || "development"
# ENV["NODE_ENV"]  ||= "development"
# ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../Gemfile",
#   Pathname.new(__FILE__).realpath)
include PyCall::Import

# PyCall.sys.path.append File.dirname(Rails.root.join('lib/dwx', 'connector'))
PyCall.sys.path.append File.dirname(Rails.root.join('lib/', 'meta_zmq'))
PyCall.sys.path.append File.dirname(Rails.root.join('lib/telegram', 'telegramf'))
# PyCall.sys.path.append File.dirname(Rails.root.join('lib/telegram', 'meta_trader'))
# PyCall.sys.path.append File.dirname(Rails.root.join('lib', 'metaapi'))
# pyfrom 'metaapi', import: :test_meta_api_synchronization
pyfrom 'telegramf', import: :'Telegramf'
pyfrom 'meta_zmq', import: :'MetaZmq'
# pyfrom 'connector', import: :'DWX_ZeroMQ_Connector'


# pyfrom 'meta_trader', import: :'MetaTrader'



def telegram_request_msg

  # # zmq = DWX_ZeroMQ_Connector.new()
  
  telegram = Telegramf.new()
  telegram.connect()
  loop do
    sleep(10)
    traces = Store.first.traces.active.telegram
    if traces.present?
      traces.each do |trace|

        # meta_receive_closed_positions(zmq)

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

def set_stop_or_limit_order(meta, instrument, open_price, ordertype)
  open_price = open_price.to_f
  tick = meta.meta.Get_last_tick_info(instrument=instrument)
  if open_price > tick['bid'] and ordertype == 'sell'
    return 'sell_limit'
  elsif open_price < tick['bid'] and ordertype == 'sell'
    return 'sell_stop'
  elsif open_price > tick['bid'] and ordertype == 'buy'
    return 'buy_stop'
  elsif open_price < tick['bid'] and ordertype == 'buy'
    return 'buy_limit'
  end
end



# def meta_receive_closed_positions(zmq)
#   # meta = MetaApi.new
#   zmq._DWX_ZMQ_HEARTBEAT_
#   closed_order = zmq.remote_recv(zmq._PULL_SOCKET)
#   if not closed_order.nil? and closed_order.include?('CLOSED')
#     print(closed_order)
#     closed_order = closed_order.split('|')
#     ticket_order = closed_order[2]
#     transaction = Transaction.find_by_ticket(ticket_order)
#     # Store.first.transactions.not_closed.each do |transaction|
#     if transaction
#       ticket = transaction.ticket.to_i
#       if transaction.can_close?
#         transaction.update(profit: closed_order[0].to_f)
#         transaction.close
#       end
#     end
#   end
# end

# def meta_get_closed_ticket_position(trace, ticket)
#   meta = MetaTrader.new(meta_host: trace.meta_host, meta_port: trace.meta_port, symbol_list:trace.symbol_list_dict)
#   meta.connect()
#   trades = meta.get_closed_positions()
#   unless trades.empty
#     ticket = ticket.to_i
#     row_number = trades.loc[trades['position_ticket'] == ticket].index.tolist().first
#     return row_number ? trades['position_ticket'][row_number] == ticket : false
#   end
#   meta.meta.Disconnect()
# end

# def receive_deals_out(meta_order={})
#   transaction = Transaction.find_by(ticket: meta_order[:positionId])
#   if transaction
#     if meta_order[:entryType] == 'DEAL_ENTRY_OUT'
#       transaction.update(profit: meta_order[:profit], price_open: meta_order[:price], open_at: meta_order[:brokerTime]) 
#       transaction.close
#     elsif meta_order[:entryType] == 'DEAL_ENTRY_IN'
#       # transaction.update(profit: meta_order[:profit], price_open: meta_order[:price], open_at: meta_order[:brokerTime]) 
#     end
#   end
# end


def meta_order_send(attributes)
  zmq = MetaZmq.new()
  zmq._trade(attributes:attributes)
end

def meta_set_sl_and_tp_order(attributes)
  zmq = MetaZmq.new()
  zmq._trade_modify(attributes:attributes)
  # meta = MetaApi.new
  # return meta.modify(ticket, take_profit, stop_loss)
  
  # meta = MetaTrader.new(meta_host: trace.meta_host, meta_port: trace.meta_port, symbol_list:trace.symbol_list_dict)
  # meta.connect()
  # response = meta.meta.Set_sl_and_tp_for_position(ticket=ticket.to_i, stoploss=stop_loss.to_f, takeprofit=take_profit.to_f)
  # meta.meta.Disconnect()
 #    return meta.meta.order_error, meta.meta.order_return_message
end

def login_check(message)
  store = Store.all.detect{|x| x.master.include?(message['account_login'])}
  if store.present?
    attributes = {account_login: message['account_login'], login_check: 1}
  else
    attributes = {account_login: message['account_login'], login_check: 0}
  return attributes
  end
end

def meta_close_order(attributes)
  zmq = MetaZmq.new()
  zmq._trade_close(attributes:attributes)
  # meta = MetaApi.new
  # return meta.close(ticket)
  # meta = MetaTrader.new(meta_host: trace.meta_host, meta_port: trace.meta_port, symbol_list:trace.symbol_list_dict)
  # meta.connect()
  # response = meta.meta.Close_position_by_ticket(ticket)
  # meta.meta.Disconnect()
  # return meta.meta.order_error, meta.meta.order_return_message
end