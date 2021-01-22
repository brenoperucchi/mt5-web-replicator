require 'lucky_case/string'
module Signals
  class SwingTradingViPSerializer < Signals::BaseSerializer
    attributes :id, :message_id, :symbol, :type, :price_request, :SL, :TP

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
      case object.trace.volumes.count
      when 1          
        [take_profit_1]
      when 2
        [take_profit_1, take_profit_2]
      end
    end

  end
end