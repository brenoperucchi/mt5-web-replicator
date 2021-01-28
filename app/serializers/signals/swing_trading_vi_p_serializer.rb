require 'lucky_case/string'
module Signals
  class SwingTradingViPSerializer < Signals::BaseSerializer
    attributes :id, :message_id, :symbol, :type, :price_request, :stoploss, :takeprofit


    def action?
      content = self.object.content.downcase
      if (object.content.include?('sell') or object.content.include?('buy')) and object.content.include?('now') and object.root?
        'open_order'
      elsif content.include?("close") or content.include?("kill")
        'close_order'
      elsif content.include?("break") or content.include?("entrie")
        "set_break_even"
      elsif (content.include?("sl") or content.include?("stop loss")) and content.include?("set") 
        object.new_value = values.first
        return "set_stop_loss"
      elsif (content.include?("tp") or content.include?("take profit")) and content.include?("set") 
        "set_take_profit"
      else
        false
      end
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