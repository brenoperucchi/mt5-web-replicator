include ActiveModel::Serialization
# require 'open-uri'
require 'json'
module API
  module V3
    class APISlave < Grape::API
      include API::V3::Defaults
      include ActiveModel::Serialization

      resource :slave do         
        # api/v3/slave/post/update/imentore_slave/3_00_02/DarwinexDemo/3000064180/HEDGING
        desc "Slave Post Receive Transaction "
        post "/post/update/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          content_type 'text/plain'
          account_server = AccountServer.find_or_create_by(name: params["account_server_name"].try(:downcase))
          account = Account.find_by(name: params["account_id"], account_server: account_server, kind: :slave, state: :enable)
          if account
            message = Message::V3::MetaSlave.create(content: content, params: params.to_json, request_url: request.url, account: account, store: account.store, content_at: Time.zone.now)
            message.request = request
            if message.execute
              status 201
              body message.response
              return true
            end
          end
          status 400
        end 

        # /api/v3/slave/post/orders/imentore_slave/3_00_02/DarwinexDemo/3000064180/HEDGING
        desc "Slave Conciliate Metatrader Transactions "
        post "/post/orders/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do          
          content_type 'text/plain'
          account_server = AccountServer.find_or_create_by(name: params["account_server_name"].try(:downcase))
          account = Account.find_by(name: params["account_id"], account_server: account_server, kind: :slave, state: :enable)
          if account
            slavePresenter = API::V3::SlavePresenter.new(params, request, nil, account)
            status 201
            body slavePresenter.slaves
          else
            status 400
          end
        end



          # presenter = API::V3::MetatraderPresenter.new(params, request)
          # presenter.execute
          # if presenter.pending_orders?
          #   status 201
          #   body presenter.response
          # else
          #   status 401
          # end

        # /api/v3/slave/post/store/imentore_slave/3_00_02/DarwinexDemo/3000064180/HEDGING
        resource :post do
          resource :store do
            desc "Return Store Config"
            post "/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
              presenter = API::V3::StorePresenter.new(params, version, request)
              if presenter.prepare && presenter.enabled?(meta_version_accept)
                status 201
                body presenter.serializer
              else
                status 400
              end
            end      
          end
        end

      end
    end
  end
end