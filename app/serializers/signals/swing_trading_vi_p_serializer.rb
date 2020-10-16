require 'lucky_case/string'
module Signals
	class SwingTradingViPSerializer < ActiveModel::Serializer
		 attributes :id, :message_id, :symbol, :type, :price_request, :SL, :TP

	  def id
	  	object.id
	  end

		def symbol
			object.symbol
		end

		def type
			object.message.split[1]
		end

		def price_request
			object.message.split[4]
		end

		def SL
			object.message.split[7]
		end

		def TP
			[object.message.split[10], object.message.split[13]]
		end

	end
end