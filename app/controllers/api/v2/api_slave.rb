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
          account = Account.find_by(name: params[:account_id], kind: :slave, state: :enable)
          if account
            map = account.slaves.opened.where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 31.days)).collect{|t| t.api_request_attributes}.join('/')
          end
          content_type 'text/plain'
          body map
        end

        desc "TransactionSlave Post Pending Transactions"
        post "/slave/post/:state/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          account = Account.find_by(name: params[:account_id], kind: :slave, state: :enable)
          if account
            map = account.slaves.opened.where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 31.days)).collect{|t| t.api_request_attributes}.join('/')
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

        desc "Slave Conciliate Metatrader Transactions "
        post "/orders_history/post/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          content_type 'text/plain'
          account = Account.find_by(name: params[:account_id])
          change = false
          return_request = "OK|OK|OK"
          if params.dig(:logfile).present?

            content   = File.open(params[:logfile][:tempfile]).try(:read)
            presenter = API::V2::APISlaveOrdersHistoryPresenter.new(content)
            disable_log = true if presenter.start_month == "1970.01.01 00:00"
            
            if account
              customer  = account.customer
              date      = DateTime.parse(presenter.start_month)
              invoice_name = "#{customer.id}-#{date.strftime("%Y-%m")}"

              invoice = customer.invoices.find_by(name: invoice_name) #, store: account.store)
              if invoice
                invoice_item = invoice.items.find_by(state: :conciliate, account:account)
                if invoice_item
                  # invoice.items.where(state: :conciliate, account:account).destroy_all
                  invoice.loggings.where(state: "CONCILIATE", account: account).destroy_all
                  invoice_item.conciliate_metatrader(presenter)
                  if invoice_item.save
                    invoice_item.conciliated!
                    invoice_item.conciliate_metatrader_off
                    invoice.conciliate_request
                    invoice.balance_update
                    Logging.create(content: presenter.json.to_json, state: "CONCILIATE", loggerable:invoice, resourceable:invoice_item, account: account)
                    change = true
                  end
                end
              end
            end
          else
            disable_log = true
          end
          unless change
            Logging.create(content: presenter&.json.to_json, state: "NOTCONCILIATE", loggerable:invoice, resourceable: invoice_item, account: account) unless disable_log
            invoice&.items&.conciliate&.map(&:conciliate_metatrader_off)
            account&.invoice_items&.map do |item| 
              if item.conciliate?
                item.conciliate_metatrader_off
                item.normal!
              end
            end
          end
          body change ? return_request : false
        end
      end
    end
  end
end