class InvoiceItemSerializer < ActiveModel::Serializer
  attributes :id, :settings
  has_one :invoice
end
