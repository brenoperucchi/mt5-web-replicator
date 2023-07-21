#!/bin/env ruby
# encoding: Windows-1252
# require 'open-uri'
require 'json'
module API
  module V220
    class APICopy < Grape::API
      include API::V220::Defaults

      resource :copy do 
        ##Copy Version >= 2.12 
        get "/get/:expert_name/:expert_version/:action/:account_server_name/:account_id/:account_mode" do
          account = Account.find_by(name: params[:account_id], kind: :copy)
          if account
            map = account.transactions.api_request_attributes(:closed_info)
          end
          content_type 'text/plain'
          body map
        end        

        ##Copy Version <= 2.11
        get "/get/:expert_name/:expert_version/:action/:account_server_name/:account_id/:account_mode" do
          account = Account.find_by(name: params[:account_id], kind: :copy)
          if account
            map = account.transactions.api_request_attributes(:closed_info)
          end
          content_type 'text/plain'
          body map
        end

        post "/post/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          content_type 'text/plain'


          account = Account.find_by(name: params[:account_id], kind: :copy)


          # request_json = params[:imentore_copy]
          # @orders_json = YAML.load(request_json) if request_json
          # params_hash  = params.except(:imentore_copy)  


          # api_version = (version == "v2") ? "V220" : "V2"
          # klass_metatrader = "Message::#{api_version}::Metatrader".classify.safe_constantize

          # hash_params = {imentore_copy:params["imentore_copy"]}.merge(params.except("imentore_copy"))

          # message = klass_metatrader.create(content: hash_params , content_at: Time.zone.now, store: account.try(:store))

          if not klass_metatrader.nil? and message.execute
            body "OK|OK|OK"
            status 201
          else
            status 401
          end
        end
      end
    end
  end
end