require 'lucky_case/string'
module Signals
  class MirfxSerializer < Signals::BaseSerializer
    attributes :id, :message_id, :symbol, :type, :price_request, :SL, :TP

    def values
      object.content.scan(/\@ (.*$)/).flatten
    end

    def type
      object.content.split[2]
    end

    def price_request
      object.content.split[5]
    end

    def SL
      object.content.split[7]
    end

    def TP
      case object.trace.take_profit.downcase
      when "normal"          
        [object.content.split[9]]
      when "agressive"
        [object.content.split[9]]
      when "superagressive"
        [object.content.split[9]]
      end
    end
    
  end
end