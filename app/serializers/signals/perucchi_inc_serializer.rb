#swing

require 'lucky_case/string'
module Signals
  class PerucchiIncSerializer < ActiveModel::Serializer
     attributes :id, :message_id, :symbol, :type, :price_request, :SL, :TP, :lots

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

    # def TP
    #   [object.message.split[10], object.message.split[13]]
    # end
    def TP
      case object.trace.take_profit.downcase
      when "normal"          
        [object.message.split[10]]
      when "agressive"
        [object.message.split[10], object.message.split[13]]
      when "superagressive"
        [object.message.split[10], object.message.split[13]]
      end
    end
    
    def lots
      case object.trace.take_profit.downcase
      when "normal"
        [ object.calcule_lot(1.00) ]
      when "agressive"
        [ object.calcule_lot(0.65), object.calcule_lot(0.35) ]
      when "superagressive"
        [ object.calcule_lot(0.65), object.calcule_lot(0.35) ]
      end
    end

  end
end