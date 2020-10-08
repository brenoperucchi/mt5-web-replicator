require 'lucky_case/string'
module Signals
	class M15SignalsPremiumSerializer < ActiveModel::Serializer
		 attributes :id, :message_id, :symbol, :type, :price_request, :SL, :TP

	  def id
	  	object.id
	  end

		def symbol
			object.symbol
		end

		def type
			object.message.split[0]
		end

		def price_request
			object.message.split[1]
		end

		def SL
			object.message.split.last
		end

		def TP
			[object.message.split[3], object.message.split[5]]
		end

	end
end