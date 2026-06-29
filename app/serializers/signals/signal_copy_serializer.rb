require 'lucky_case/string'
module Signals
  class SignalCopySerializer < Signals::BaseSerializer


    def content
      YAML.load(object.read_attribute(:content))
    end

    def action?
      return 'open_order', nil
    end

    def values
      object.content.scan(/(\d*\.\d+)/).flatten
    end


    def ordertype
      content['order_type'].to_i
      # when "0"
      #   "OP_BUY"
      # when '1'
      #   'OP_SELL'
      # when '2'
      #   'OP_BUY_LIMIT'
      # when '3'
      #   'OP_BUY_STOP'
      # when '4'
      #   'OP_SELL_LIMIT'
      # when '5'
      #   'OP_SELL_STOP'
      # end
    end

    def ticket
      content['order_ticket']
    end

    def type
      ordertype
    end

    def volume(value=nil)
      content['volume']
    end

    def value(arg)
      begin
        values[arg].try(:strip)
      rescue
        nil
      end
    end

    def takeprofits
      [1]
    end

    def price_request
      content['open_price']
    end

    def stoploss
     content['stop_loss']
    end

    def take_profit_1
      content['take_profit']
    end

    def take_profit_2
      content['take_profit']
    end

    def takeprofit
      case object.trace.take_profit_limit.to_i
      when 1          
        [take_profit_1]
      when 2
        [take_profit_1, take_profit_2]
      else
        [take_profit_1, take_profit_2, take_profit_2]
      end
    end

    def symbol
      content['order_symbol']
    end

  end
end