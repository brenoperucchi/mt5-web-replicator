#!/bin/env ruby
# encoding: Windows-1252
# require 'open-uri'
require 'json'
module API
  module V1
    class APITransactionsCopy < Grape::API
      include API::V1::Defaults

      resource :transactions do 
        get "/copy/trasmit/:expert_name/:expert_version/:action/:account_id/:account_mode" do
          account = Account.find_by(name: params[:account_id], kind: :copy)
          if account
            map = account.transactions.api_request_attributes(:closed_info)
          end
          content_type 'text/plain'
          body map
        end

        post "/copy/trasmit/:expert_name/:expert_version/:action/:account_id/:account_mode" do
          content_type 'text/plain'
          action = params[:action]
          if action == "closed"
            parameters = eval(params[:body].encode("UTF-8", "Windows-1252"))
            serializer_attributes = SerializerAPITransaction.new(YAML.load(params[:body].encode("UTF-8", "Windows-1252")))
            # transaction = Transaction.find_by(ticket: parameters[:deal_ticket])
            # Transaction.executed.where(ticket: parameters[:deal_ticket]).each do |transaction|
            Transaction.where(ticket: parameters[:ticket_id]).each do |transaction|
              
              transaction.attributes = {price_closed:  parameters[:close_price], profit: parameters[:profit], closed_at:serializer_attributes.open_at}
              transaction.save
              transaction.loggings.create(content:params, state: action.try(:upcase), changeset: transaction.try(:versions).try(:last).try(:changeset))
              
              if transaction.can_close?
                if transaction.close 
                  transaction.slaves.each do |slave|
                    slave.loggings.create(content: "Remove automatically by API Transaction Copy Action Closed ##{transaction.id}", state: "REMOVE")
                  end
                end
              end
            end
            body "OK|OK|OK"
          elsif action == "orders"    
            # TODO - Aceitar registro de message de copy mesmo se conta desabilitada 
            account = Account.find_by(name: params[:account_id], kind: :copy, state: :enable)
            if account
              account.loggings.create(content:params, state: action.try(:upcase), changeset: account.name)
              trace = account.try(:trace_copy)

              if trace #and not content.blank? and content.is_a?(Hash)
                orders = {orders:[]}
                params['orders'].encode("UTF-8", "Windows-1252").split("//").each do |order| 
                  orders[:orders] << [YAML.load(order)]
                end
                orders[:params] = params.except('orders')
                message = Message::Metatrader.create(content: orders.to_json, content_at: Time.zone.now, store: trace.store, trace:trace)
                
                # TODO - Colocar uma trava se account estiver desabilitado
                if message.execute
                  if account.transactions.closed_info.present?
                    body account.transactions.api_request_attributes(:closed_info)
                  else  
                    body "OK|OK|OK"
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