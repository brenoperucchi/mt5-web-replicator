require 'lucky_case/string'
module Signals
  class M15SignalsPremiumSerializer < Signals::BaseSerializer
    attributes :id, :message_id, :symbol, :type, :price_request, :SL, :TP

    def values
      object.message.scan(/\@ (.*$)/).flatten
    end

    def type
      object.message.split[0]
    end

    def price_request
      object.message.split[1]
    end

    def SL
      object.message.split.last
    end

    def TP
      case object.trace.volumes.count
      when 1          
        [object.message.split[3]]
      when 2
        [object.message.split[3], object.message.split[5]]
      when 3
        [object.message.split[3], object.message.split[5]], object.message.split[7]]
      end
    end
  
  end
end