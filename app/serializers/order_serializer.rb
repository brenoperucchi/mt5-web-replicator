class OrderSerializer < ActiveModel::Serializer
  attributes :id, :content_id, :symbol, :trace_id, :message_id, :account_id, :store_id, :deal_id, :execute_at, :created_at

    def trace
      object.trace.name
    end
  # has_one :sign_trace

end
