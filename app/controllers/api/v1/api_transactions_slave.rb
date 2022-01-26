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
        get "/request/:state/:expert_name/:expert_version/:account_id/:account_mode" do
          account = Account.find_by(name: params[:account_id])
          if account
            # map = account.slaves.send(params[:state]).collect{|t| t.api_request_attributes}.join('/')
            map = account.slaves.entire.collect{|t| t.api_request_attributes}.join('/')
          end
          content_type 'text/plain'
          body map
        end

        desc "Request Pending Transactions"
        post "/request/:state/:expert_name/:expert_version/:account_id/:account_mode" do
          account = Account.find_by(name: params[:account_id])
          if account
            # map = account.slaves.collect{|t| t.api_request_attributes}.join('/')
            # map = account.slaves.send(params[:state]).collect{|t| t.api_request_attributes}.join('/')
            map = account.slaves.entire.collect{|t| t.api_request_attributes}.join('/')
          end
          content_type 'text/plain'
          body map
        end   
        desc "Receive Transaction"
        post "/trasmit/:expert_name/:expert_version/:account_id/:account_mode" do
          map = String.new
          message = params[:body]
          content = YAML.load(message)
          if not content.blank? and content.is_a?(Hash)
            action = content['action']
            # trace = Trace.find(content['comment'].split("-").first)
            account = Account.find(content['comment'].split("-").first)
            # transaction_id = content['comment'].split("-").last
            slave = account.slaves.find_by(ticket_master: content['comment'].split("-").last)
            if slave.nil?
              Logging.create(content:message)
            else
              slave.loggings.create(content:message)
              case action
              when "CLOSED", "DELETED"
                # slave = Transaction.find_by(id: content['comment'].split("-")[1]).slaves.first if trace.copy?
                api_attributes = APITransactionSlaveSerializer.new(message).api_attributes.merge(profit:content['profit'])
                slave.attributes = api_attributes
                action == "CLOSED" ? slave.close : slave.deleted
                map = "#{slave.master.trace.id}|#{slave.id}|OK"
              when "MODIFY"
                slave.set_sl_and_tp_order(content['take_profit'], content['stop_loss'])
                map = "#{slave.master.trace.id}|#{slave.id}|OK"
              when "OPENED"
                api_attributes = APITransactionSlaveSerializer.new(message).api_attributes
                slave.update(api_attributes.merge(state:'executed', profit:nil))
                map = "#{slave.master.trace.id}|#{slave.id}|OK"
              when "NOSLTP","ERRORDEAL","TIMEMAX"
                if action == "NOSLTP"
                  api_attributes = APITransactionSlaveSerializer.new(message).api_attributes.merge(stop_loss:0, take_profit:0)
                else
                  api_attributes = APITransactionSlaveSerializer.new(message).api_attributes
                end
                # slave.update(api_attributes.merge(state:'error', profit:nil))
                slave.erro
                map = "#{slave.master.trace.id}|#{slave.id}|OK"
              end
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