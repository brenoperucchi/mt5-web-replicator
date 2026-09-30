#!/bin/env ruby
# encoding: Windows-1252
# require 'open-uri'
require 'json'
module API
  module V2
    class APICopy < Grape::API
      include API::V2::Defaults

      resource :copy do 

        post "/post/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          content_type 'text/plain'
          API::V2::APICopyPresenter.api_copy(params, request)
          body "OK|OK|OK"
          status 201
        end

        resource :post do

          # "/api/v2/copy/post/orders/imentore_copy/2_30_05/DarwinexDemo/3000064179/HEDGING" (length: 117)
          resource :orders do
            post "/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
              content_type 'text/plain'
              presenter = API::V2::APICopyPresenter.api_copy(params, request)
              if presenter.execute
                body "OK|OK|OK"
                status 201
              else
                status 400
              end
            end
          end
          
          # "/api/v2/copy/post/store/imentore_copy/2_30_05/DarwinexDemo/3000064179/HEDGING" (length: 116)
          resource :store do
            desc "Return Store Config"
            post "/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
              presenter = API::V2::StorePresenter.new(params, version, request)
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