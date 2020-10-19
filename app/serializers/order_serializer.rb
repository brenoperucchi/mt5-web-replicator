class OrderSerializer < ActiveModel::Serializer
  attributes :id, :message_id, :message, :active_at, :symbol
  # has_one :sign_trace

end
