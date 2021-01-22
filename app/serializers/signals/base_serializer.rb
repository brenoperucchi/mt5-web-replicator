#swing
require 'lucky_case/string'
module Signals
  class BaseSerializer < ActiveModel::Serializer
    attributes :id, :message_id, :symbol, :type, :price_request, :SL, :TP

    def id
      object.id
    end

    def symbol
      object.symbol
    end


  end
end