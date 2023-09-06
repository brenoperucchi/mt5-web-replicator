include ActiveModel::Serialization
# require 'open-uri'
require 'json'
module API
  module V2
    class APISlave < Grape::API
      include API::V2::Defaults
      include ActiveModel::Serialization

      resource :transactions do 
        desc "Example Request Transaction"
        get "/slave/get/:state/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          account = Account.find_by(name: params[:account_id])
          if account
            map = account.slaves.opened.where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 3.days)).collect{|t| t.api_request_attributes}.join('/')
          end
          content_type 'text/plain'
          body map
        end

        desc "Request Pending Transactions"
        # get "/slave/get/:state/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
        post "/slave/post/:state/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          account = Account.find_by(name: params[:account_id])
          if account
            map = account.slaves.opened.where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 3.days)).collect{|t| t.api_request_attributes}.join('/')
          end
          content_type 'text/plain'
          body map
        end   
        desc "Receive Transaction"
        post "/slave/post/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          map = String.new
          message = params[:body]
          content = YAML.load(message)
          date_today = DateTime.now
          skip_logging = false;

          if not content.blank? and content.is_a?(Hash)
            action = content['meta_state']
            account_server = AccountServer.find_or_create_by(name: params[:account_server_name].try(:downcase))
            account = Account.find_by(name: params[:account_id], account_server: account_server, state: :enable, kind: :slave)
            if account
              # TransactionSlave.check_duplicate(content['comment'], account)
              slave = account.slaves.where(comment: content['comment']).not_deleted.first
              order = Order.find_by(content: content['comment'])  

              if slave.nil?
                Logging.create(content:message, state: action, parent: order.try(:message).try(:loggings).try(:first), account: account)
              else
                case action
                when "OPEN", "OPENED"
                  api_attributes = SerializerAPITransactionSlave.new(message).api_attributes
                  slave.attributes = api_attributes
                  slave.execute
                  @version = slave.versions.last
                  map = "#{slave.master.trace.id}|#{slave.id}|OK"
                when "CLOSED", "DELETED", "HASCLOSED"
                  api_attributes = SerializerAPITransactionSlave.new(message).api_attributes.merge(profit:content['profit'])
                  slave.attributes = api_attributes
                  
                  if slave.closed? and slave.loggings.count < 4 and slave.loggings.detect(&:detect_closed?).nil?
                    slave.state = :executed
                    slave.master.state = :executed
                  end                  
                  # action == "CLOSED" ? slave.close : slave.deleted
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
                when "NOTMODIFY"
                  logging_count  = slave.loggings.where(state: action, ancestry: slave.loggings.last.ancestry, account_id: slave.account.id, created_at:date_today.beginning_of_day..date_today.end_of_day).count
                  if logging_count >= 2
                    action = "NOSLTP"
                    skip_logging = true if slave.loggings.where(state: action, created_at:date_today.beginning_of_day..date_today.end_of_day).present?                    
                    # api_attributes = SerializerAPITransactionSlave.new(message).api_attributes.merge(stop_loss:0, take_profit:0).except(:price_open, :price_closed)
                    # slave.attributes = api_attributes
                    # slave.save
                    @version = slave.versions.last
                  end
                when "NOTFIND"
                  slave.erro
                  @version = slave.versions.last
                when "NOSLTP","ERRORDEAL","TIMEMAX", "NOTCLOSED"
                  if action == "NOSLTP" or action == "NOTCLOSED"
                    skip_logging = true if slave.loggings.where(state: action, created_at:date_today.beginning_of_day..date_today.end_of_day).present?
                    # api_attributes = SerializerAPITransactionSlave.new(message).api_attributes.merge(stop_loss:0, take_profit:0).except(:price_open, :price_closed)
                    # slave.attributes = api_attributes
                    # slave.save
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
                # message << params.except("body").to_s.delete('\\"')
                slave.loggings.create(content:message, changeset: @version.try(:changeset), version:@version, state: action, parent: slave.loggings.first, account: slave.account, loggerable: slave.order.messages.last) unless skip_logging

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