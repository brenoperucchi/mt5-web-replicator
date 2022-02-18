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
            map = account.slaves.opened.where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 3.days)).collect{|t| t.api_request_attributes}.join('/')
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
            map = account.slaves.opened.where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 3.days)).collect{|t| t.api_request_attributes}.join('/')
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
            account = Account.find_by(name: params[:account_id])
            # binding.pry

            # account_id = content['comment'].split("-").first
            # account = Account.find_by(id: account_id, state: :enable)
            # transaction_id = content['comment'].split("-").last
            if account
              slave = account.slaves.find_by(comment: content['comment'])
              # slave = account.slaves.find_by(ticket_master: content['comment'].split("-").last)
              if slave.nil?
                Logging.create(content:message)
              else
                case action
                when "CLOSED", "DELETED"
                  api_attributes = APITransactionSlaveSerializer.new(message).api_attributes.merge(profit:content['profit'])
                  slave.attributes = api_attributes
                  if slave.closed? and slave.loggings.count < 2 and slave.loggings.detect(&:detect_closed?).nil?
                    slave.state = :executed
                    slave.master.state = :executed
                  end
                  action == "CLOSED" ? slave.close : slave.deleted
                  map = "#{slave.master.trace.id}|#{slave.id}|OK"
                when "MODIFY"
                  slave.set_sl_and_tp_order(content['take_profit'], content['stop_loss'])
                  map = "#{slave.master.trace.id}|#{slave.id}|OK"
                when "OPENED"
                  api_attributes = APITransactionSlaveSerializer.new(message).api_attributes
                  slave.attributes = api_attributes
                  slave.execute
                  map = "#{slave.master.trace.id}|#{slave.id}|OK"
                when "NOSLTP","ERRORDEAL","TIMEMAX"
                  if action == "NOSLTP"
                    api_attributes = APITransactionSlaveSerializer.new(message).api_attributes.merge(stop_loss:0, take_profit:0)
                  else
                    api_attributes = APITransactionSlaveSerializer.new(message).api_attributes
                    slave.erro
                  end
                  # slave.update(api_attributes.merge(state:'error', profit:nil))
                  map = "#{slave.master.trace.id}|#{slave.id}|OK"
                end
                slave.loggings.create(content:message)
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