#!/bin/env ruby
# encoding: Windows-1252
# require 'open-uri'
require 'json'
module API
  module V3
    class APICopy < Grape::API
      include API::V3::Defaults

      resource :copy do 
        resource :post do

          # "/api/v3/copy/post/orders/imentore_copy/2_30_05/DarwinexDemo/3000064179/HEDGING" (length: 117)
          resource :orders do
            post "/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
              content_type 'text/plain'
              account_server = AccountServer.find_or_create_by(name: params["account_server_name"].try(:downcase))
              account = Account.find_by(name: params["account_id"], account_server: account_server, kind: :copy, state: :enable)
              message = Message::V3::MetaCopy.create(content: content, params: params.to_json, request_url: request.url, account: account, store: account.store, content_at: Time.zone.now)
              # message.request = request
              if account && message.execute
                status 201
                return true
              end
              status 400
            end
          end
          
          # "/api/v3/copy/post/store/imentore_copy/2_30_05/DarwinexDemo/3000064179/HEDGING" (length: 116)
          resource :store do
            desc "Return Store Config"
            post "/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
              # logging = Logging.create(state: "CONFIG", request_url: request.url, params: params)
              presenter = API::V3::StorePresenter.new(params, version, request)
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
  end
end