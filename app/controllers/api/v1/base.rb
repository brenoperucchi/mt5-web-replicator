module API
  module V1
    class Base < Grape::API
      mount API::V1::Traces
      # mount API::V1::ApiOrders
      mount API::V1::APITransactionsSlave
      mount API::V1::APITransactionsCopy
      mount API::V1::Stores
    end
  end
end