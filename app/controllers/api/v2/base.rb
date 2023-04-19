module API
  module V2
    class Base < Grape::API
      mount API::V2::APITransactionsSlave
      mount API::V2::APITransactionsCopy
      mount API::V2::APIStore
    end
  end
end