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

          account = Account.find_by(name: params[:account_id], kind: :copy, state: :enable)
          return if account.nil?

          request_json = params[:imentore_copy]
          @orders_json = YAML.load(request_json) if request_json
          params_hash  = params.except(:imentore_copy)  

          if @orders_json["orders_closed"].present?
            content_json = {imentore_copy: {orders_closed: @orders_json["orders_closed"]}}.merge(params_hash).to_json
            account.loggings.create(content:content_json, state: "ORDERS_CLOSED", changeset: account.name)
            
            changed = true;
            @orders_json["orders_closed"].each_with_index do |(ticket, copy_params), index|
              Transaction.where(ticket: ticket).each do |transaction|
                if transaction and not transaction.closed?
                  transaction.attributes = {price_closed:  copy_params["close_price"], profit: copy_params["profit"], closed_at:copy_params["close_at"]}
                  transaction.save
                  transaction.loggings.create(content:content_json, state: "CLOSED", changeset: transaction.try(:versions).try(:last).try(:changeset))
                  transaction.set_mfe_mae(copy_params["mfe"], copy_params["mae"], copy_params["time_trader"]) 
                  
                  # if transaction.can_close?
                    if transaction.close 
                      
                      transaction.slaves.each do |slave|
                        slave.loggings.create(content: "Remove automatically by Close Orders #{transaction.id}", state: "CLOSED_INFO", resourceable:account, changeset: transaction.try(:versions).try(:last).try(:changeset))
                      end
                    else
                      changed = false
                    end
                  # end
                end
              end
            end
            if changed
              body "OK|OK|OK"
              status 201
            else
              status 401
            end
          end
          
          if @orders_json["orders_open"].present?
            # TODO - Aceitar registro de message de copy mesmo se conta desabilitada 
            account = Account.find_by(name: params[:account_id], kind: :copy)
            if account
              content_json = {imentore_copy: {orders_open: @orders_json["orders_open"]}}.merge(params_hash).to_json
              
              traces = account.traces.copy
              if traces.present? #and not content.blank? and content.is_a?(Hash)
                message = Message::Metatrader.create(content: @orders_json, content_at: Time.zone.now, store: account.store, traces:traces)
                # TODO - Colocar uma trava se account estiver desabilitado
                if not message.error? and @orders_json["orders_open"].try(:present?)
                  # content = YAML.load(self.content)
                  account_mode = params[:account_mode]
                  account_copy = Account.find_by(name: params[:account_id])
                  account.loggings.create(content:content_json, state: "ORDERS_OPEN", changeset: account.name)
                  changed = true

                  @orders_json["orders_open"].each_with_index do |(ticket, copy_params), index|
                    # copy_attributes = API::V220::APICopySerializer.new(copy_params).api_attributes
                    state_meta = copy_params["state_meta"]
                    traces.active.not_deleted.each do |trace|
                      orders = trace.orders.where(content_id: ticket)
                      if not orders.present?
                        unless trace.create_orders(copy_params, account_copy, message, copy_params["symbol"], version) 
                          changed ||= false
                        end

                      elsif state_meta.try(:include?, "SLTPLOT")
                        @orders_json.each do |order| 
                          order.transactions.each do|t| 
                            t.set_lot_sl_tp(copy_params) 
                            t.set_mfe_mae(copy_params["mfe"], copy_params["mae"], copy_params["time_trader"])
                          end
                        end

                      elsif state_meta.try(:include?, "SLTPLOT")
                        @orders_json.each do |order| 
                          order.transactions.each do |t| 
                            t.set_profit(order_params["profit"])
                            t.set_mfe_mae(copy_params["mfe"], copy_params["mae"], copy_params["time_trader"])
                          end
                        end
                      end
                    end
                  end

                  if changed
                    body "OK|OK|OK"
                    status 201
                  else
                    status 401
                  end
                  
                else
                  content_error = "Message::Metatrader ##{message.try(:id)} cannot executed - Account Name #{account.try(:name)}"
                  account.loggings.create(content:content_error, state: "ERROR", changeset: message.try(:errors).try(:full_messages))
                  body :NONE
                end
              end
            end
          end
        end
      end
    end
  end
end