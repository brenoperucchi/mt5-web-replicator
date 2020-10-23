require 'lucky_case/string'
module Signals
  class M15SignalsPremiumSerializer < Signals::BaseSerializer
    attributes :id, :message_id, :symbol, :type, :price_request, :SL, :TP, :lots

    def values
      object.message.scan(/\@ (.*$)/).flatten
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
      case object.trace.take_profit.downcase
      when "normal"          
        [object.message.split[3]]
      when "agressive"
        [object.message.split[3], object.message.split[5]]
      when "superagressive"
        [object.message.split[3], object.message.split[5], object.message.split[7]]
      end
    end
    
    def lots
      case object.trace.take_profit.downcase
      when "normal"
        [ object.calcule_lot(1.00) ]
      when "agressive"
        [ object.calcule_lot(0.65), object.calcule_lot(0.35) ]
      when "superagressive"
        [ object.calcule_lot(0.65), object.calcule_lot(0.35), object.calcule_lot(0.35) ]
      end
    end
  
  end
end