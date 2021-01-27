require 'lucky_case/string'
module Signals
  class PipsNationSerializer < Signals::BaseSerializer
    attributes :id, :message_id, :symbol, :type, :price_request, :stoploss, :takeprofit

    def prepare?
      (object.content.downcase.include?('sell') or object.content.downcase.include?('buy'))
    end

    def values
      object.content.scan(/\@ (.*$)/).flatten
    end

    def symbol
      object.content.split[0].upcase
    end

    def type
      object.content.split[3].downcase
    end

    def price_request
      object.content.split[4]
    end

    def stoploss
      object.content.split[14]
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