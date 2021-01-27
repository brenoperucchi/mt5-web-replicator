require 'lucky_case/string'
module Signals
  class SwingTradingViPSerializer < Signals::BaseSerializer
    attributes :id, :message_id, :symbol, :type, :price_request, :stoploss, :takeprofit

    def prepare?
      (object.content.downcase.include?('sell') or object.content.downcase.include?('buy')) and object.content.downcase.include?('now')
    end

    def symbol
      object.content.split[0].upcase
    end

    def values
      object.content.scan(/\@ (.*$)/).flatten
    end

    def type
      object.content.split[1]
    end

    def value(arg)
      begin
        values[arg].gsub(' ', '.')
      rescue
        nil
      end
    end

    def takeprofits
      object.content.scan('(/PT\d+ @ [\d.]+/)')
    end

    def price_request
      value(0)
    end

    def stoploss
      value(1)
    end

    def take_profit_1
      value(2)
    end

    def take_profit_2
      value(3)
    end

    def takeprofit
      case object.trace.volumes.count
      when 1          
        [take_profit_1]
      when 2
        [take_profit_1, take_profit_2]
      else
        [take_profit_1, take_profit_2, take_profit_2]
      end
    end

  end
end