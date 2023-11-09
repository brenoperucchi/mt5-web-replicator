include ActiveModel::Serialization
# require 'open-uri'
require 'json'
module API
  module V2
    class APISlave < Grape::API
      include API::V2::Defaults
      include ActiveModel::Serialization

      resource :transactions do 
        desc "TransactionSlave Get Request Transaction"
        get "/slave/get/:state/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          account = Account.find_by(name: params[:account_id])
          if account
            map = account.slaves.opened.where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 3.days)).collect{|t| t.api_request_attributes}.join('/')
          end
          content_type 'text/plain'
          body map
        end

        desc "TransactionSlave Post Pending Transactions"
        post "/slave/post/:state/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          account = Account.find_by(name: params[:account_id])
          if account
            map = account.slaves.opened.where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 3.days)).collect{|t| t.api_request_attributes}.join('/')
          end
          content_type 'text/plain'
          body map
        end   
        desc "TransactionSlave Receive Transaction"
        post "/slave/post/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          map = API::V2::APISlavePresenter.api_slave(params, version, request)
          body map
        end   
      end

      resource :slave do 
        desc "Slave Post Receive Transaction "
        post "/post/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          content_type 'text/plain'
          map = API::V2::APISlavePresenter.api_slave(params, version, request)
          body map
        end   
      end

    end
  end
end