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
        get "/ddns/update" do

          # #################### CHANGE THE FOLLOWING VARIABLES ####################
          # TOKEN="dop_v1_a92aca07ea5626dfb9ff2aae559c2e08ef89121b1b948c1af5e78085b0875058"
          # DOMAIN="imentore.com.br"
          # RECORD_ID="327101812"
          # LOG_FILE="ips.txt"
          # ########################################################################

          # CURRENT_IPV4="$(dig +short myip.opendns.com @resolver1.opendns.com)"
          # LAST_IPV4="$(tail -1 $LOG_FILE | awk -F, '{print $2}')"

          # if [ "$CURRENT_IPV4" = "$LAST_IPV4" ]; then
          #     echo "IP has not changed ($CURRENT_IPV4)"
          # else
          #     echo "IP has changed: $CURRENT_IPV4"
          #     echo "$(date),$CURRENT_IPV4" >> "$LOG_FILE"
          #     curl -X PUT -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d '{"data":"'"$CURRENT_IPV4"'"}' "https://api.digitalocean.com/v2/domains/$DOMAIN/records/$RECORD_ID"
          status 200
        end      
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
            account.loggings.create(content:attributes, state: "START") unless result
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