module API
  module V1
    class Base < Grape::API
      # mount API::V1::SignSlave
      mount API::V1::SignTraces
      mount API::V1::SignOrders
      mount API::V1::Stores
    end
  end
end