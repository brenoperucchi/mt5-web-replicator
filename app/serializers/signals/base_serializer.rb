#swing
require 'lucky_case/string'
module Signals
  class BaseSerializer < ActiveModel::Serializer
	attributes :id, :message_id, :symbol, :type, :price_request, :SL, :TP
	
	def id
	  object.id
	end

	def transaction_attributes(response={})
	  {
		ticket: response[:ticket], 
		symbol: symbol, 
		ordertype: type, 
		price_request: price_request, 
		take_profit: response[:takeprofit], 
		lot: response[:volume], 
		magic_number: response[:magicnumber], 
		comment: object.trace.name,
		response: response[:response],
		response_error: response[:response_error],
		open_at: response[:open_at],
		stop_loss: stoploss,
		message_id: object.id 
	  }
	end

	def meta_attributes(value)
	  @meta_attributes = { 
		instrument: symbol,
		ordertype: type,
		volume:object.trace.volumes.map(&:name)[value],
		openprice: price_request,
		slippage:10,
		magicnumber:2000,
		stoploss: stoploss,
		takeprofit:takeprofit[value],
		comment:object.trace.name
	  }
	end


	def order_attributes
	  {symbol: symbol, content:object.content.html_safe, content_id: object.content_id}
	end

	# def symbol
	#   object.symbol
	# end


  end
end