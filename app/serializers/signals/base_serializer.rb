require 'lucky_case/string'
module Signals
  class BaseSerializer < ActiveModel::Serializer
		attributes :id, :symbol, :type, :price_request, :stoploss, :takeprofit
		
		def id
		  	object.id
		end

		def transaction_attributes(value=0)
		  	{
				ticket: ticket,
				ordertype: ordertype, 
				price_request: price_request, 
				take_profit: takeprofit[value], 
				magic_number: object.trace.name_id.delete("-"), 
				stop_loss: stoploss,
				message_id: object.id,
				order_id: object.try(:order).try(:id),
		  	}
		end

		def ticket
		  nil
		end

		def ordertype
			case type.downcase
			when "buy"
				0
			when 'sell'
				1
			when 'buy_limit'
				2
			when 'sell_limit'
				3
			when 'buy_stop'
				4
			when 'sell_stop'
				5
			end
		end

		def order_attributes
	 		# {symbol: symbol, content:object.content.html_safe, content_id: object.content_id}
	 		{content:object.content.html_safe, content_id: object.content_id}
		end

  end
end