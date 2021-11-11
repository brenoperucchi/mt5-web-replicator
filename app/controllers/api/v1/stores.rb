require 'json'
module API
  module V1
    class Stores < Grape::API
      include API::V1::Defaults
      format :json
      formatter :json, 
           Grape::Formatter::ActiveModelSerializers

      resource :stores do
        desc "Return all signs"
        get "/telegram/python" do
          Store.active
        end      
      end
    end
  end
end