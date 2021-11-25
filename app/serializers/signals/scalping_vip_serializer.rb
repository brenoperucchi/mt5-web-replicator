require 'lucky_case/string'
module Signals
  class ScalpingVipSerializer < Signals::BaseSerializer

    def action?
      content = self.object.content.downcase
      # if (object.content.include?('sell') or object.content.include?('buy')) and object.content.include?('now') and object.root?
      if content.include?('sell') or content.include?('buy')
        return 'open_order', nil
      elsif content.include?("break") or content.include?("entrie") or (content.include?("entry") and content.include?("sl")) or (content.include?("be") and content.include?("sl"))
        return "set_break_even", break_even
      elsif (content.include?("sl") or content.include?("stop loss")) and content.include?("set") 
        return "set_stop_loss", break_even
      elsif (content.include?("tp") or content.include?("take profit")) and content.include?("set") 
        return "set_take_profit", values.first
      elsif content.include?("close") or content.include?("kill")
        return 'close_order', nil
      else
        return false, nil
      end
    end

    def values
      object.content.scan(/(\d*\.\d+)/).flatten
    end


    def break_even
      values.empty? ? object.root.serializer.price_request : values.first
    end               

    def type
      type_order = ""
      if object.content.downcase.include?('buy')
        type_order += 'buy'
      elsif object.content.downcase.include?('sell')
        type_order += 'sell'
      end

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
      # REV 7
      object.content.scan(/(?:TP\d?)(?:[^\d]*)(\d*\.\d+)/i).flatten
                           
      #REV 6 - (TP\d?:? *)([[:digit:].]+)
      #REV 8 - ^(?:(?<direction>buy|sell)? *(?<pair>[a-z]{6}) *(?(1)|(?<direction>buy|sell)) *@ *(?<entry>[\d.]+)|\G(?!\A)(?:sl:? *(?<sl>[\d.]+)|tp\d?:? *(?<tp>[\d.]+)) *(?:\((?<pips>[\d.]+)\))?)\s*
      #REV 9 - ^(?:(?<direction>buy|sell)? *(?<pair>[a-z]{6}) *(?(1)|(?<direction>buy|sell)) *@ *(?<entry>[\d.]+)|\G(?!\A)(?<type>sl|tp)\d?:? *(?<price>[\d.]+) *(?:\((?<pips>[\d.]+)\))?)\s*
    end

    def price_request
      value(0)
    end

    def stoploss
      stoploss = object.content.scan(/(?:SL\d?)(?:[^\d]*)(\d*\.\d+)/i).flatten.first
      stoploss ||= 50.to_s
    end

    def take_profit_1
      takeprofits[0]
    end

    def take_profit_2
      takeprofits[1]
    end

    def take_profit_3
      takeprofits[1]
    end

    def takeprofit
      case object.trace.take_profit_limit.to_i
      when 1          
        [take_profit_1]
      when 2
        [take_profit_1, take_profit_2]
      else
        [take_profit_1, take_profit_2, take_profit_3]
      end
    end


  end
end