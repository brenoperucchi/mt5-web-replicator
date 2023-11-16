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
          account = Account.find_by(name: params[:account_id], kind: :slave, state: :enable)
          if account
            map = account.slaves.opened.where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 3.days)).collect{|t| t.api_request_attributes}.join('/')
          end
          content_type 'text/plain'
          body map
        end

        desc "Request Pending Transactions"
        post "/request/:state/:expert_name/:expert_version/:account_id/:account_mode" do
          account = Account.find_by(name: params[:account_id], kind: :slave, state: :enable)
          if account
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
            action = content['meta_state']
            account = Account.find_by(name: params[:account_id], kind: :slave, state: :enable)
            if account
              slave = account.slaves.find_by(comment: content['comment'])
              if slave.nil?
                Logging.create(content:message, state: action)
              else
                case action
                when "OPEN"
                  api_attributes = SerializerAPITransactionSlave.new(message).api_attributes
                  slave.attributes = api_attributes
                  slave.execute
                  @version = slave.versions.last
                  map = "#{slave.master.trace.id}|#{slave.id}|OK"
                when "CLOSED", "DELETED", "HASCLOSED"
                  api_attributes = SerializerAPITransactionSlave.new(message).api_attributes.merge(profit:content['profit']).except(:price_open)
                  slave.attributes = api_attributes
                  if slave.closed? and slave.loggings.count < 4 and slave.loggings.detect(&:detect_closed?).nil?
                    slave.state = :executed
                    slave.master.state = :executed
                  end
                  if action == "CLOSED" or action == "HASCLOSED"
                    slave.close
                  else
                    slave.deleted
                  end
                  @version = slave.versions.last(2).try(:first)
                  map = "#{slave.master.trace.id}|#{slave.id}|OK"
                when "MODIFY"
                  slave.set_sl_and_tp_order(nil, content['take_profit'], content['stop_loss'])
                  @version = slave.versions.last
                  map = "#{slave.master.trace.id}|#{slave.id}|OK"
                when "MODIFY_VOLUME"
                  @version = slave.versions.last
                  map = "#{slave.master.trace.id}|#{slave.id}|OK"                  
                when "NOTFIND"
                  slave.erro
                  @version = slave.versions.last
                when "NOSLTP","ERRORDEAL","TIMEMAX"
                  if action == "NOSLTP"
                    api_attributes = SerializerAPITransactionSlave.new(message).api_attributes.merge(stop_loss:0, take_profit:0).except(:price_open, :price_closed)
                    slave.attributes = api_attributes
                    slave.save
                    @version = slave.versions.last
                  else
                    api_attributes = SerializerAPITransactionSlave.new(message).api_attributes
                    slave.erro
                    @version = slave.versions.last
                  end
                  @version = slave.versions.last
                  map = "#{slave.master.trace.id}|#{slave.id}|OK"
                end
                logging_content = nil
                message << params.except("body").to_s.delete('\\"')
                slave.loggings.create(content:message, changeset: @version.try(:changeset), version:@version, state: action)
              end
            else
              Logging.create(content:message, state: action)
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