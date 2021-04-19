#swing
require 'lucky_case/string'
module Signals
  class BaseSerializer < ActiveModel::Serializer
	attributes :id, :symbol, :type, :price_request, :stoploss, :takeprofit
	
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

	def meta_attributes(value=0)
		openprice = (type.include?('limit') or type.include?('stop')) ? price_request : 0
		instrument = object.trace.instruments.find_by_symbol(symbol)

	  	@meta_attributes = { 
			instrument: symbol,
			ordertype: type,
			volume:instrument.volumes.try(:split,', ')[value],
			openprice: openprice,
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


	def symbol
		object.trace.instruments.detect{|x| object.content.gsub(/\W/, '').upcase.include?(x[:symbol].upcase) }.try(:name)
	end

	# def symbol
	#   object.symbol
	# end


  end
end