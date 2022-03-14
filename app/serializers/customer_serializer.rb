class CustomerSerializer < ActiveModel::Serializer
  attributes :id, :name, :active_at
  has_one :user
end
