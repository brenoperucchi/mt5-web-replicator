#!/bin/env ruby
# encoding: Windows-1252
# require 'open-uri'
require 'json'
module API
  module V2
    class APICopy < Grape::API
      include API::V2::Defaults

      resource :copy do 
        ##Copy Version >= 2.12 
        get "/get/:expert_name/:expert_version/:action/:account_server_name/:account_id/:account_mode" do
          account = Account.find_by(name: params[:account_id], kind: :copy, state: :enable)
          if account
            map = account.transactions.api_request_attributes(:closed_info)
          end
          content_type 'text/plain'
          body map
        end        

        ##Copy Version <= 2.11
        get "/get/:expert_name/:expert_version/:action/:account_server_name/:account_id/:account_mode" do
          account = Account.find_by(name: params[:account_id], kind: :copy, state: :enable)
          if account
            map = account.transactions.api_request_attributes(:closed_info)
          end
          content_type 'text/plain'
          body map
        end

        post "/post/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          content_type 'text/plain'
          API::V2::APICopyPresenter.api_copy(params, version, request)
          body "OK|OK|OK"
          status 201

        end
      end
    end
  end
end