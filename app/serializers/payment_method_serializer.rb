class PaymentMethodSerializer < ActiveModel::Serializer
  attributes :id, :name, :handle
end
