module API
  module V220
    class Base < Grape::API
      mount API::V220::APISlave
      mount API::V220::APICopy
      mount API::V220::APIStore
    end
  end
end