class	API::V3::StorePresenter < API::V3::BasePresenter

	attr_accessor :params, :version, :request, :logging, :serializer, :account, :meta_version_accept, :status

	def initialize(params, version, request, meta_version_accept)
		@params = params
		@version = version
		@request = request
		@meta_version_accept = meta_version_accept
		
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

	def account_server
		account_server_name = params[:account_server_name].try(:downcase)
		account_server = AccountServer.find_or_create_by(name:account_server_name)
	end

	def prepare
		@account = Account.find_by(name: account_name, state: :enable, kind: kind, account_server:nil)
		
		if account
		  account.update(account_server: account_server)
		  @logging = logging.update(content:params.to_json, account: account)
		else
		  @account = Account.find_by(name: account_name, state: :disable, kind: kind, account_server:account_server)
	    logging.update(content: account_name, params: params.to_json, state: "ACCOUNTNOTFOUND", account: @account) if Logging.where(content: account_name, state: "ACCOUNTNOTFOUND",  created_at:date_today.beginning_of_day..date_today.end_of_day, account: @account).count < 1
		end
	end	

	def execute
		@account = Account.find_by(name: account_name, state: :enable, kind: kind, account_server: account_server)

		if @account.present? and @account.enable?
			attributes = {meta_version_accept: meta_version_accept, account: self.try(:account).nil?, expert_name: kind, account_serializer: @serializer}
			result = account.loggings.find_by(state: "START", created_at:date_today.beginning_of_day..date_today.end_of_day)
			if account && account.store.enable? && meta_version_accept
			  logging.update(content:attributes.to_json, state: "START", account:account) unless result
			  @status = 201
			  @serializer = AccountSerializer.new(account, params: @params).try(:attributes)
			else 
			  logging.update(content:attributes.to_json, state: "NOTSTART", account:account) if account.loggings.where(content:attributes.to_json, state: "NOTSTART",  created_at:date_today.beginning_of_day..date_today.end_of_day).count < 2
			  @status = 401
			end
		else
			@status = 403
		end
	end

end