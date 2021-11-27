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

        desc "Return Store Config"
        post "/config/:expert_name/:expert_version/:account_id" do
          account = Account.find_by(name: params[:account_id])
          store = account.store
        end      
      end
    end
  end
end