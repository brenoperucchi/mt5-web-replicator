require 'lucky_case/string'
module Signals
  class CanalEasyTraderRobotDolarSerializer < Signals::BaseSerializer
    attributes :id, :message_id, :symbol, :type, :price_request, :stoploss, :takeprofit

    def action?
      content = self.object.content.downcase
      # if (object.content.include?('sell') or object.content.include?('buy')) and object.content.include?('now') and object.root?
      if (content.include?('venda') or content.include?('compra')) and not content.include?('start')
        return 'open_order', nil
      elsif content.include?("fechar") or content.include?("close")
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
      object.content.tr("@",'').scan(/[(\s\d.*$\^@)]+/)
    end

    def symbol
      'BRADOL'
    end

    def check_limit_stop_order_type?
      false
    end

    def type
      if object.content.downcase.include?('venda')
        @price_request = object.content.scan(/VENDA:[(\s\d.*$\^@)]+/).first.split(':').last.strip
        'sell'
      elsif object.content.downcase.include?('compra')
        @price_request = object.content.scan(/COMPRA:[(\s\d.*$\^@)]+/).first.split(':').last.strip
        'buy'
      end
      # if object.content.downcase.include?('stop')
      #   type_order += '_stop'
      # elsif object.content.downcase.include?('limit')
      #   type_order += '_limit'
      # end
      # type_order
    end

    def value(arg)
      begin
        values[arg].gsub(' ', '')
      rescue
        nil
      end
    end

    def round_up(number)
      return 0 if number.nil?
      number = (number.to_i/10).to_s + "5" if (number.to_i % 5) !=0 
      number.to_i
    end

    def price_request
      @price_request
    end

    def stoploss
      split = object.content.scan(/Loss:[(\s\d.*$\^@)]+/).first.try(:split, ':')
      round_up(split.try(:last).try(:strip))
    end

    def take_profit_1
      split = object.content.scan(/Gain:[(\s\d.*$\^@)]+/).first.try(:split, ':')
      round_up(split.try(:last).try(:strip))
    end

    def takeprofit
      case object.trace.volumes.count
      when 1          
        [take_profit_1]
      when 2
        [take_profit_1]
      else
        [take_profit_1]
      end
    end

  end
end