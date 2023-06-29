module API
  module V2
    class Base < Grape::API
      mount API::V2::APISlave
      mount API::V2::APICopy
      mount API::V2::APIStore
    end
  end
end