class PlanPaymentSerializer < ActiveModel::Serializer
  attributes :id, :name, :settings, :amount
  has_one :store
end
