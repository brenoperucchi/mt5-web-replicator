require 'lucky_case/string'
module Signals
  class SwingTradingViPSerializer < Signals::BaseSerializer
    attributes :id, :message_id, :symbol, :type, :price_request, :SL, :TP, :lots

    def values
      object.message.scan(/\@ (.*$)/).flatten
    end

    def type
      object.message.split[1]
    end

    def value(arg)
      begin
        values[arg].gsub(' ', '.')
      rescue
        nil
      end
    end

    def price_request
      value(0)
    end

    def SL
      value(1)
    end

    def take_profit_1
      value(2)
    end

    def take_profit_2
      value(3)
    end

    def TP
      case object.trace.take_profit.downcase
      when "normal"          
        [take_profit_1]
      when "agressive"
        [take_profit_1, take_profit_2]
      when "superagressive"
        [take_profit_1, take_profit_2]
      end
    end
    
    def lots
      case object.trace.take_profit.downcase
      when "normal"
        [ object.trace.lots ]
      when "agressive"
        [ object.calcule_lot(0.65), object.calcule_lot(0.35) ]
      when "superagressive"
        [ object.calcule_lot(0.55), object.calcule_lot(0.45) ]
      end
    end

  end
end