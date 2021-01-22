class TransactionSerializer < ActiveModel::Serializer
  attributes :id, :ticket, :symbol

    # def trace
    #   object.trace.name
    # end
  # has_one :sign_trace

end
