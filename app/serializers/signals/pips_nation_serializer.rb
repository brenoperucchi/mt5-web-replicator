require 'lucky_case/string'
module Signals
  class PipsNationSerializer < Signals::BaseSerializer
    attributes :id, :message_id, :symbol, :type, :price_request, :stoploss, :takeprofit

    def values
      object.content.scan(/(\d.*$)/).flatten
    end

    def action?
      content = self.object.content.downcase
      if (content.include?('sell') or content.include?('buy')) and object.root?
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

    def symbol
      object.content.split[0].upcase
    end

    def type
      type_order = object.content.split[3].downcase
      if object.content.downcase.include?('stop')
        type_order += '_stop'
      elsif object.content.downcase.include?('limit')
        type_order += '_limit'
      end
      type_order
    end

    def price_request
      object.content.split[4]
    end

    def stoploss
      object.content.split[14] || 0
    end

    def takeprofit
      case object.trace.volumes.count
      when 1          
        [object.content.split[6]]
      when 2
        [object.content.split[6], object.content.split[8]]
      when 3
        [object.content.split[6], object.content.split[8], object.content.split[10]]
      when 4
        [object.content.split[6], object.content.split[8], object.content.split[10], object.content.split[12]]
      end
    end
     
  end
end