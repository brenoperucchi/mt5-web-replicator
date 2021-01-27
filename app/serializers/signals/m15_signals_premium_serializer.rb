require 'lucky_case/string'
module Signals
  class M15SignalsPremiumSerializer < Signals::BaseSerializer
    attributes :id, :message_id, :symbol, :type, :price_request, :SL, :TP

    def values
      object.content.scan(/\@ (.*$)/).flatten
    end

    def type
      object.content.split[0]
    end

    def price_request
      object.content.split[1]
    end

    def SL
      object.content.split.last
    end

    def TP
      case object.trace.volumes.count
      when 1          
        [object.content.split[3]]
      when 2
        [object.content.split[3], object.content.split[5]]
      when 3
        [object.content.split[3], object.content.split[5]], object.content.split[7]]
      end
    end
  
  end
end