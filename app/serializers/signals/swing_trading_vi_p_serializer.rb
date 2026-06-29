require 'lucky_case/string'
module Signals
  class SwingTradingViPSerializer < Signals::BaseSerializer

    def action?
      content = self.object.content.downcase
      # if (object.content.include?('sell') or object.content.include?('buy')) and object.content.include?('now') and object.root?
      if (content.include?('sell') or content.include?('buy')) and (content.include?('now') or content.include?('limit') or content.include?('stop'))
        return 'open_order', nil
      elsif content.include?("close") or content.include?("kill")
        return 'close_order', nil
      elsif content.include?("break") or content.include?("entrie")
        return "set_break_even", values.first
      elsif (content.include?("sl") or content.include?("stop loss")) and content.include?("set") 
        return "set_stop_loss", values.first
      elsif (content.include?("tp") or content.include?("take profit")) and content.include?("set") 
        return "set_take_profit", values.first
      else
        return false, nil
      end
    end

    def values
      object.content.scan(/(\d*\.\d+)/).flatten
    end

    # def symbol
    #   object.content.split[0].upcase
    # end

    def type
      type_order = object.content.split[1].downcase
      if object.content.downcase.include?('stop')
        type_order += '_stop'
      elsif object.content.downcase.include?('limit')
        type_order += '_limit'
      end
      type_order
    end

    def value(arg)
      begin
        values[arg].try(:strip)
      rescue
        nil
      end
    end

    def takeprofits
      object.content.scan(/(?:TP\d?)(?::| @| ) ?(\d*\.\d+)/i).flatten
    end

    def price_request
      value(0)
    end

    def stoploss
      value(1).to_f
    end

    def take_profit_1
      value(2).to_f
    end

    def take_profit_2
      value(3).to_f
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

  end
end