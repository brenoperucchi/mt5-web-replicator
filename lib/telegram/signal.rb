#!/usr/bin/env ruby
require File.expand_path('../../../config/environment', __FILE__)
require 'pycall/import'
# require "pathname"

# ENV["RAILS_ENV"] ||= ENV["RACK_ENV"] || "development"
# ENV["NODE_ENV"]  ||= "development"
# ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../Gemfile",
#   Pathname.new(__FILE__).realpath)

include PyCall::Import
PyCall.sys.path.append File.dirname(Rails.root.join('lib/telegram', 'telegramf'))
PyCall.sys.path.append File.dirname(Rails.root.join('lib/telegram', 'meta_trader'))
pyfrom 'telegramf', import: :'Telegramf'
pyfrom 'meta_trader', import: :'MetaTrader'

def telegram_request_msg
	telegram = Telegramf.new()
	telegram.connect()
	loop do
		traces = Store.first.traces.active
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
										store: Store.first
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
									root_message.store = Store.first
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

def meta_order_send(trace, meta_attributes)
	meta = MetaTrader.new(meta_host: trace.meta_host, meta_port: trace.meta_port, symbol_list:trace.symbol_list_dict)
	meta.connect()

	if message.serializer.try(:check_limit_stop_order_type?)
		meta_attributes[:ordertype] = set_stop_or_limit_order(meta, meta_attributes[:instrument], meta_attributes[:openprice], meta_attributes[:ordertype])
	end

	response = meta.order_send(meta_attributes: meta_attributes)
	meta.meta.Disconnect()
	return response
end

def meta_get_closed_positions(trace)
	meta = MetaTrader.new(meta_host: trace.meta_host, meta_port: trace.meta_port, symbol_list:trace.symbol_list_dict)
	meta.connect()
	trades = meta.get_closed_positions()
	unless trades.empty
		Store.first.transactions.not_closed.each do |transaction|
			ticket = transaction.ticket.to_i
			row_number = trades.loc[trades['order_ticket'] == ticket].index.tolist().first
			if row_number
				if trades['order_ticket'][row_number] == ticket
					row_hash = trades.loc[trades['order_ticket'] == ticket].to_dict
					transaction = Transaction.find_by(ticket: ticket)
					transaction.update(profit: trades['profit'][row_number], response: row_hash, price_open: trades['open_price'][row_number], open_at: Time.at(trades['open_time'][row_number].to_i) )
					transaction.close
				end
			end
		end
	end
	meta.meta.Disconnect()
end

def meta_get_open_positions(transaction, trace)
	meta = MetaTrader.new(meta_host: trace.meta_host, meta_port: trace.meta_port, symbol_list:trace.symbol_list_dict)
	meta.connect()
	trades = meta.meta.Get_all_open_positions()
	unless trades.empty
		ticket = transaction.ticket.to_i
		row_number = trades.loc[trades['ticket'] == ticket].index.tolist().first
		if row_number
			if trades['ticket'][row_number] == ticket
				row_hash = trades.loc[trades['ticket'] == ticket].to_dict
				transaction = Transaction.find_by(ticket: ticket)
				transaction.update(response: row_hash,
					price_open: trades['open_price'][row_number], open_at: Time.at(trades['open_time'][row_number].to_i) )
			end
		end
	end
	meta.meta.Disconnect()
end

def meta_set_sl_and_tp_order(ticket=nil, take_profit=nil, stop_loss=nil, trace=nil)
	meta = MetaTrader.new(meta_host: trace.meta_host, meta_port: trace.meta_port, symbol_list:trace.symbol_list_dict)
	meta.connect()
	response = meta.meta.Set_sl_and_tp_for_position(ticket=ticket.to_i, stoploss=stop_loss.to_f, takeprofit=take_profit.to_f)
	meta.meta.Disconnect()
    return meta.meta.order_error, meta.meta.order_return_message
end

def meta_close_order(ticket, trace)
	meta = MetaTrader.new(meta_host: trace.meta_host, meta_port: trace.meta_port, symbol_list:trace.symbol_list_dict)
	meta.connect()
	response = meta.meta.Close_position_by_ticket(ticket)
	meta.meta.Disconnect()
	return meta.meta.order_error, meta.meta.order_return_message
end