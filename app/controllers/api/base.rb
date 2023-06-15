module API
  class Base < Grape::API
    mount API::V1::Base
    mount API::V2::Base
    mount API::V220::Base
  end
end