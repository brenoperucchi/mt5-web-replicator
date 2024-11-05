class	API::V3::StorePresenter < API::V3::BasePresenter

	attr_accessor :params, :version, :request, :logging, :serializer, :account

	def initialize(params, version, request)
		@params = params
		@version = version
		@request = request
		
	end

	def kind
		@kind = params[:expert_name].include?('slave') ? 'slave' : 'copy'
	end

	def date_today
		@date_today = DateTime.current
	end

	def logging
		@logging ||= Logging.create(state: "CONFIG", request_url: request.url, params: params)
	end

	def account_name
		account_name = params[:account_id]
	end

	def prepare
		account_server_name = params[:account_server_name].try(:downcase)
		
		account_server = AccountServer.find_or_create_by(name:account_server_name)
		@account = Account.find_by(name: account_name, state: :enable, kind: kind, account_server:nil)
		

		if account
		  account.update(account_server: account_server)
		  @logging = logging.update(content:params.to_json, account: account)
		else
		  @account = Account.find_by(name: account_name, state: :enable, kind: kind, account_server:account_server)
		  if account.nil?
		    logging.update(content:params.to_json, state: "ACCOUNTNOTFOUND") if Logging.where(content:params.to_json, state: "ACCOUNTNOTFOUND",  created_at:date_today.beginning_of_day..date_today.end_of_day).count < 2
		    return false
		  end
		end
		
		if account.nil?
			return
		else
			@serializer = AccountSerializer.new(account, params: @params).try(:attributes)
		end
		

		def enabled?(meta_version_accept)
			attributes = {meta_version_accept: meta_version_accept, account: self.try(:account).nil?, expert_name: kind, account_serializer: @serializer}
			result = account.loggings.find_by(state: "START", created_at:date_today.beginning_of_day..date_today.end_of_day)
			if account && account.store.enable? && meta_version_accept
			  logging.update(content:attributes.to_json, state: "START", account:account) unless result
			  return true
			else 
			  logging.update(content:attributes.to_json, state: "NOTSTART", account:account) if account.loggings.where(content:attributes.to_json, state: "NOTSTART",  created_at:date_today.beginning_of_day..date_today.end_of_day).count < 2
			  return false
			end
		end

  end
end