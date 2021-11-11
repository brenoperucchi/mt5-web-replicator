include ActiveModel::Serialization
# require 'open-uri'
require 'json'
module API
  module V1
    class APITransactionsSlave < Grape::API
      include API::V1::Defaults
      include ActiveModel::Serialization

      resource :transactions do 
        desc "Example Request Transaction"
        get "/request/:state/:expert_name/:expert_version/:account_id" do
          account = Account.find_by(name: params[:account_id])
          if account
            map = account.slaves.send(params[:state]).collect{|t| t.api_request_attributes}.join('/')
          end
          content_type 'text/plain'
          body map
        end

        desc "Request Pending Transactions"
        post "/request/:state/:expert_name/:expert_version/:account_id" do
          account = Account.find_by(name: params[:account_id])
          if account
            # map = account.slaves.collect{|t| t.api_request_attributes}.join('/')
            map = account.slaves.send(params[:state]).collect{|t| t.api_request_attributes}.join('/')
          end
          content_type 'text/plain'
          body map
        end   
        desc "Receive Transaction"
        post "/trasmit/:expert_name/:expert_version/:account_id" do
          map = String.new
          message = params[:body]
          content = YAML.load(message)
          if not content.blank? and content.is_a?(Hash)
            transaction_id = content['comment'].split("|").last
            slave = TransactionSlave.find_by(id: transaction_id)
            return unless slave
            slave.loggings.create(content:message)
            case content['action']
            when "CLOSED", "DELETED"
              api_attributes = APITransactionSerializer.new(message).api_attributes
              slave.update(api_attributes.merge(state: content['action'].downcase))
              map = "#{slave.transaction_master.order.trace.id}|#{slave.id}|OK"
            when "MODIFY"
              master = slave.transaction_master
              master.set_sl_and_tp_order(content['take_profit'], content['stop_loss'])
              map = "#{slave.transaction_master.order.trace.id}|#{slave.id}|OK"
            when "OPENED"
              api_attributes = APITransactionSerializer.new(message).api_attributes
              slave.update(api_attributes.merge(state:'executed', profit:nil))
              map = "#{slave.transaction_master.order.trace.id}|#{slave.id}|OK"
            end
            content_type 'text/plain'
            body map
          end
        end   
        ##############################################
      end
    end
  end
end