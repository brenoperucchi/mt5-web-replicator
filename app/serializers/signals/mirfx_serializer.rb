require 'lucky_case/string'
module Signals
  class MirfxSerializer < Signals::BaseSerializer
    attributes :id, :message_id, :symbol, :type, :price_request, :SL, :TP

    def values
      object.message.scan(/\@ (.*$)/).flatten
    end

    def type
      object.message.split[2]
    end

    def price_request
      object.message.split[5]
    end

    def SL
      object.message.split[7]
    end

    def TP
      case object.trace.take_profit.downcase
      when "normal"          
        [object.message.split[9]]
      when "agressive"
        [object.message.split[9]]
      when "superagressive"
        [object.message.split[9]]
      end
    end
    
  end
end