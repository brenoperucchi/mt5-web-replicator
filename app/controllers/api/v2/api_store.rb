require 'json'
module API
  module V2
    class APIStore < Grape::API
      include API::V2::Defaults
      format :json
      # formatter :json, 
      #      Grape::Formatter::ActiveModelSerializers
      


      resource :stores do
        desc "Return all signs"
        get "/telegram/python" do
          Store.enable
        end      

        # desc "Return Store Config"
        # get "/config/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
        #   kind = params[:expert_name].include?('slave') ? 'slave' : 'copy'
        #   account = Account.find_by(name: params[:account_id], state: 1, kind: kind)
        #   account && account.store.enable? ? account.store : nil 
        # end
        desc "Return Store Config"
        get "/config/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          kind = params[:expert_name].include?('slave') ? 'slave' : 'copy'
          account = Account.find_by(name: params[:account_id], state: 1, kind: kind)
          if account && account.store.enable? && meta_version_accept
            AccountSerializer.new(account, params:params) 
          else 
            status 400
          end
        end      
        desc "Return Store Config"
        post "/config/:expert_name/:expert_version/:account_server_name/:account_id/:account_mode" do
          date_today = DateTime.now
          kind = params[:expert_name].include?('slave') ? 'slave' : 'copy'
          account_server_name = params[:account_server_name].try(:downcase)
          account_name = params[:account_id]
          account_server = AccountServer.find_or_create_by(name:account_server_name)

          account = Account.where(name: account_name, state: 1, kind: kind, account_server:nil).try(:last)

          if account
            account.update(account_server: account_server)
          else
            account = Account.where(name: account_name, kind: kind, account_server:account_server).try(:last)
            if account.nil?
              Logging.create(content:params.to_json, state: "ACCOUNTNOTFOUND") if Logging.where(content:params.to_json, state: "ACCOUNTNOTFOUND",  created_at:date_today.beginning_of_day..date_today.end_of_day).count < 2
              status 400
              return
            end
          end

          return true if account.nil?
          
          @account_serializer = AccountSerializer.new(account, params:params) 

          attributes = {meta_version_accept: meta_version_accept, account: self.try(:account).nil?, expert_name: kind, account_serializer: @account_serializer}
          result = account.loggings.find_by(state: "START", created_at:date_today.beginning_of_day..date_today.end_of_day)
          if account && account.store.enable? && meta_version_accept
            account.loggings.create(content:attributes, state: "START") unless result
            # AccountSerializer.new(account, params:params) 
            status 201
            return @account_serializer
          else 
            account.loggings.create(content:attributes, state: "NOTSTART") if account.loggings.where(content:attributes, state: "NOTSTART",  created_at:date_today.beginning_of_day..date_today.end_of_day).count < 2
            status 400
          end
        end      
      end
    end
  end
end