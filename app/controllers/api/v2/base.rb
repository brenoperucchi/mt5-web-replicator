module API
  module V2
    class Base < Grape::API
      # mount API::V2::Orders
      # mount API::V1::Slaves
      # mount API::V1::Traces
      # mount API::V1::Stores
    end
  end
end