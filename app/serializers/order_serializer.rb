class OrderSerializer < ActiveModel::Serializer
  attributes :id, :message_id, :message, :symbol
  # has_one :sign_trace

end
