require 'json'
module API
  module V1
    class APIStore < Grape::API
      include API::V1::Defaults
      format :json
      # formatter :json, 
      #      Grape::Formatter::ActiveModelSerializers
      


      resource :stores do
        desc "Return all signs"
        get "/telegram/python" do
          Store.enable
        end      

        # desc "Return Store Config"
        # get "/config/:expert_name/:expert_version/:account_id/:account_mode" do
        #   kind = params[:expert_name].include?('slave') ? 'slave' : 'copy'
        #   account = Account.find_by(name: params[:account_id], state: 1, kind: kind)
        #   account && account.store.enable? ? account.store : nil 
        # end
        desc "Return Store Config"
        get "/config/:expert_name/:expert_version/:account_id/:account_mode" do
          kind = params[:expert_name].include?('slave') ? 'slave' : 'copy'
          account = Account.find_by(name: params[:account_id], state: 1, kind: kind)
          if account && account.store.enable? && meta_version_accept
            AccountSerializer.new(account, params:params) 
          else 
            nil 
          end
        end      
        desc "Return Store Config"
        post "/config/:expert_name/:expert_version/:account_id/:account_mode" do


          # attributes = {meta_version_accept: meta_version_accept, account: self.try(:account), account_serializer: account_serializer.attributes}

          kind = params[:expert_name].include?('slave') ? 'slave' : 'copy'


          account = Account.find_by(name: params[:account_id], state: 1, kind: kind)
          date_today = Date.today.in_time_zone
          return true if account.nil?
          
          @account_serializer = AccountSerializer.new(account, params:params) 

          attributes = {meta_version_accept: meta_version_accept, account: self.try(:account).nil?, expert_name: kind, account_serializer: @account_serializer}

          result = account.loggings.find_by(state: "START", created_at:date_today.beginning_of_day..date_today.end_of_day)
          if account && account.store.enable? && meta_version_accept
            account.loggings.create(content:attributes, state: "START")
            # AccountSerializer.new(account, params:params) 
            @account_serializer
          else 
            account.loggings.create(content:attributes, state: "NOT START")
            nil 
          end
        end      
      end
    end
  end
end