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

          # Logging.create(content:params, state: "COPY")
          account = Account.find_by(name: params[:account_id], kind: :copy)
          
          klass_metatrader = "Message::#{version.upcase}::Metatrader".classify.safe_constantize
          attributes = {content: params["imentore_copy"], params: params.except("imentore_copy").merge({request_url: request.url}).to_json, content_at: Time.zone.now, store: account.try(:store), account:account}

          # Message Open
          message_open = klass_metatrader.new(attributes)
          if(message_open.save)
            logging = message_open.loggings.create(content:params, state: "COPY/OPEN", changeset: account.name, account: account)
            message_open.execute if message_open.create_orders(logging)
          end

          # Message Close
          message_close = klass_metatrader.new(attributes)
          if(message_close.save)
            logging = message_close.loggings.create(content:params, state: "COPY/CLOSE", changeset: account.name, account: account)
            message_close.execute if message_close.close_orders(logging)
          end

          message_open.executed? and message_close.executed?

          if not message_open.traces.exists? and not message_open.orders.exists? and not message_open.slaves.exists?
            message_open.destroy
          end
          if not message_close.traces.exists? and not message_close.orders.exists? and not message_close.slaves.exists?
            message_close.destroy
          end
        
          # if(message_open.executed? and message_close.executed?)
          # else
          #   status 401
          # end
          body "OK|OK|OK"
          status 201
        end
      end
    end
  end
end