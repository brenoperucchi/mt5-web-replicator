module API
  module V1
    class Base < Grape::API
      # mount API::V1::Slaves
      mount API::V1::Traces
      mount API::V1::Orders
      mount API::V1::Transactions
      mount API::V1::Stores
    end
  end
end