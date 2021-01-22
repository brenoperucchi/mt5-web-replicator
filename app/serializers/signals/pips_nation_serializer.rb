require 'lucky_case/string'
module Signals
  class PipsNationSerializer < Signals::BaseSerializer
    attributes :id, :message_id, :symbol, :type, :price_request, :SL, :TP

    def values
      object.message.scan(/\@ (.*$)/).flatten
    end

    def type
      object.message.split[3]
    end

    def price_request
      object.message.split[4]
    end

    def SL
      object.message.split[14]
    end

    def TP
      case object.trace.volumes.count
      when 1          
        [object.message.split[6]]
      when 2
        [object.message.split[6], object.message.split[8]]
      when 3
        [object.message.split[6], object.message.split[8], object.message.split[10]]
      when 4
        [object.message.split[6], object.message.split[8], object.message.split[10], object.message.split[12]]
      end
    end
     
  end
end