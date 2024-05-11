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

        desc "Slave Post Receive Transaction "
        post "/orders_history/post/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          content_type 'text/plain'
          account = Account.find_by(name: params[:account_id])

          if account
            customer = account.customer
            content = File.open(params[:logfile][:tempfile]).try(:read)

            presenter = API::V2::APISlaveOrdersHistoryPresenter.new(content)
            date = DateTime.parse(presenter.start_month)
            invoice_name = "#{customer.id}-#{date.strftime("%Y-%m")}"

            invoice = customer.invoices.find_by(name: invoice_name) #, store: account.store)
            if invoice
              invoice_item = invoice.items.find_by(state: :conciliate, account:account)
              if invoice_item
                invoice.items.where(name: :conciliate, account:account).destroy_all
                invoice.loggings.where(state: "CONCILIATE", account: account).destroy_all
                invoice_item.conciliate_metatrader(presenter)
                if invoice_item.save
                  invoice_item.conciliated!
                  invoice_item.conciliate_metatrader_off
                  invoice.to_paid!
                  invoice.balance_update
                  account.loggings.create(content: presenter.json.to_json, state: "CONCILIATE", loggerable:invoice, resourceable:invoice_item)
                end
              else
                account.loggings.create(content: presenter.json.to_json, state: "NOTCONCILIATE", loggerable:invoice)
              end
            else
              account.loggings.create(content: presenter.json.to_json, state: "NOTCONCILIATE")
            end
            map = "OK|OK|OK"
          else
            Logging.create(content: presenter.json.to_json, state: "NOTCONCILIATE")  
          end
          body map
        end
      end
    end
  end
end