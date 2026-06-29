require 'lucky_case/string'
module Signals
  class PipsMasterSerializer < Signals::BaseSerializer

    def values
      object.content.scan(/ [(\d.*$\^@)]+/).flatten
    end

    def action?
      content = self.object.content.downcase
      if (content.include?('sell') or content.include?('buy')) and (not content.include?('limit') or not content.include?('stop'))
        return 'open_order', values.first
      elsif content.include?("break") or content.include?("even")
        return 'set_break_even', values.first
      elsif content.include?("close") or content.include?("kill")
        return 'close_order', values.first
      elsif (content.include?("sl") or content.include?("stop loss")) and content.include?("set") 
        return 'set_stop_loss', values.first
      elsif (content.include?("tp") or content.include?("take profit")) and content.include?("set") 
        return 'set_take_profit', values.first
      else
        return false, nil
      end
    end

    def value(arg)
      begin
        values[arg].try(:strip)
      rescue
        nil
      end
    end


    def takeprofits
      object.content.scan(/TP: [\d.]+/)
    end


    def symbol
      object.content.split[1].upcase
    end

    def type
      object.content.split[0].downcase
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
      value(2)
    end

    def take_profit_3
      value(2)
    end

    def take_profit_4
      value(2)
    end

    def takeprofit
      case object.trace.take_profit_limit.to_i
      when 1          
        [take_profit_1]
      when 2
        [take_profit_1, take_profit_2]
      when 3
        [take_profit_1, take_profit_2, take_profit_3]
      when 4
        [take_profit_1, take_profit_2, take_profit_3, take_profit_4]
      end
    end  
  
  end
end