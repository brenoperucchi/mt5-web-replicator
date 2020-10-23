class OrderSerializer < ActiveModel::Serializer
  attributes :id, :message_id, :message, :symbol, :trace

    def trace
      object.trace.name
    end
  # has_one :sign_trace

end
