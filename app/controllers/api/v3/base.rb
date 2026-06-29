module API
  module V3
    class Base < Grape::API
      mount API::V3::APISlave
      mount API::V3::APICopy
      mount API::V3::APIStore
    end
  end
end