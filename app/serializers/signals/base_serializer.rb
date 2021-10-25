#swing
require 'lucky_case/string'
module Signals
  class BaseSerializer < ActiveModel::Serializer
	attributes :id, :symbol, :type, :price_request, :stoploss, :takeprofit
	
	def id
	  	object.id
	end

	def transaction_attributes(meta=nil, value=0)
		instrument = object.trace.instruments.find_by_symbol(symbol)
	  	{
			ticket: ticket,
			symbol: symbol, 
			ordertype: ordertype, 
			# price_open: meta.try(:position)['openPrice'],
			price_request: price_request, 
			take_profit: takeprofit[value], 
			lot: instrument.volumes.try(:split,', ')[value], 
			magic_number: object.trace.name_id, 
			# comment: object.trace.name,
			# response: meta.try(:response, ['message']),
			# response_error: meta.try(:response, ['numericCode']),
			# open_at: meta.try(:response, ['tradeStartTime']),
			stop_loss: stoploss,
			message_id: object.id,
			# meta_order_generate: meta.try(:response),
	  	}
	end

	def ticket
	  nil
	end

	def ordertype
		# "OP_" + type.upcase
		case type.downcase
		when "buy"
			0
		when 'sell'
			1
		when 'buy_limit'
			2
		when 'buy_stop'
			3
		when 'sell_limit'
			4
		when 'sell_stop'
			5
		end
	end

	# def meta_attributes(value=0, transaction)
	# 	# openprice = (type.include?('limit') or type.include?('stop')) ? price_request : 0
	# 	instrument = object.trace.instruments.find_by_symbol(symbol)

	#   	@meta_attributes = { 
	# 		instrument: symbol,
	# 		ordertype: ordertype,
	# 		volume:instrument.volumes.try(:split,', ')[value],
	# 		openprice: price_request,
	# 		slippage:10,
	# 		magic_number:transaction.magic_number,
	# 		stoploss: stoploss,
	# 		takeprofit:takeprofit[value],
	# 		trace_id: object.trace.id,
	# 		transaction_id: transaction.id,
	# 		ticket: nil
	#   	}
	# end


	def order_attributes
	 	{symbol: symbol, content:object.content.html_safe, content_id: object.content_id}
	end


	def symbol
		object.trace.instruments.detect{|x| object.content.gsub(/\W/, '').upcase.include?(x[:symbol].upcase) }.try(:name)
	end

	# def symbol
	#   object.symbol
	# end


  end
end