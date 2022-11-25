class PlanPaymentItemSerializer < ActiveModel::Serializer
  attributes :id, :name, :settings, :amount
  has_one :plan_payment
end
