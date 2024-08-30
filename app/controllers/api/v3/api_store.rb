require 'json'
module API
  module V3
    class APIStore < Grape::API
      include API::V3::Defaults
      format :json
      # formatter :json, 
      #      Grape::Formatter::ActiveModelSerializers
      
      resource :stores do
        desc "Return all signs"
        get "/telegram/python" do
          Store.enable
        end      

        # api/v3/copy/post/store/imentore_copy/2_30_05/DarwinexDemo/3000064179/HEDGING
        desc "Return Store Config"
        get "/config/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          kind = params[:expert_name].include?('slave') ? 'slave' : 'copy'
          account = Account.find_by(name: params[:account_id], state: 1, kind: kind)
          if account && account.store.enable? && meta_version_accept
            AccountSerializer.new(account, params:params) 
          else 
            status 400
          end
        end      
        
        # api/v3/copy/post/store/imentore_copy/2_30_05/DarwinexDemo/3000064179/HEDGING
        desc "Return Store Config"
        post "/config/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          logging = Logging.create(state: "CONFIG", request_url: request.url, params: params)
          presenter = API::V2::StorePresenter.new(params, version, logging)
          if presenter.prepare && presenter.enabled?(meta_version_accept)
            status 201
            return presenter.serializer
          else
            status 400
          end
        end      

      end
    end
  end
end