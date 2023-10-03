class DashboardsController < ApplicationController
	# skip_before_action :after_sign_in_path_for
	before_action :set_account, only:[:account]
	before_action :set_trace, except: [:index, :account]
	before_action :filters#, except: :index
	before_action :dashboard_restrict

	# before_action :authenticate_user
	# layout 'stisla'
  layout 'modernize'
  # layout 'mintone'

	# before_action :sign_up!


	# def sign_up!
	# 	redirect_to new_user_session_path if !user_signed_in?
			
	# end

	def finish
		trace 	 = Trace.find_by(name: params[:name])
		account = Account.find(params[:account_id])
		
		invoice_name = "Trace##{@trace.id}-Account##{account.id}-#{Time.zone.now.strftime("%Y-%m")}" 
		account.create_invoice_account(@trace, invoice_name, nil)
		@invoice = account.customer.invoices.first
		@payment = @invoice.invoice_send
		if @payment.redirect_url
			redirect_to @payment.redirect_url
		else
			render :finish
		end
	end

	def contract
		# @contract_volume = params.dig([:account][:settings][:contract_volume]) || 1
		@trace.customer_plan.promotion_use = true if params[:promotion] == "promotion"
		respond_to do |wants|
			wants.js { render layout: false }
			wants.html do  
				@account = @trace.accounts.new
			end
		end
	end

	# def create
	# 	resource_persisted = params[:resource_persisted]
	# 	customer = Customer.find_by(id: params[:account][:customer_attributes][:id])
	# 	if resource_persisted.to_b and customer
	# 		@account = customer.accounts.first
	# 		@invoice = customer.invoices.first
	# 		@payment = @invoice.payment_method
	# 		respond_to do |wants|
	# 			wants.js { render :create_success, layout: false }
	# 			wants.html { render "mercado_pago" }
	# 		end
	# 		return true
	# 	end

	# 	sign_out if user_signed_in?
	# 	password = Devise.friendly_token.first(6)
	# 	customer_plan_id = params[:customer_plan_id]
	# 	account = @trace.accounts.new(account_params)
	# 	account.state = "enable"
	# 	# account.customer.store = current_store
	# 	account.customer.role = "customer"
	# 	account.customer.role_control = "user"
	# 	account.customer.user.password = password
	# 	account.traces << @trace		

	# 	if @trace.valid? and account.save
	# 		plan_usage = account.add_account_trace_to_planusage(@trace, customer_plan_id)
	# 		customer_plan = plan_usage.usageable
	# 		customer_plan.promotion_use = true if params[:promotion] == "promotion"
	# 		customer_plan.save
	# 		invoice_name = "Trace##{@trace.id}-Account##{account.id}-#{Time.zone.now.strftime("%Y-%m")}" 
	# 		account.customer.create_invoice_customer(invoice_name)
	# 		@customer.create_user(email: @customer.user_email, password: password)
	# 		redirect_to finish_dashboard_path(@trace.name, account)

	# 		# invoice_name = "Trace##{@trace.id}-Account##{account.id}-#{Time.zone.now.strftime("%Y-%m")}" 
	# 		# account.create_invoice_account(@trace, invoice_name, nil)
	# 		# @invoice = account.customer.invoices.first
	# 		# # @payment = @invoice.invoice_send
	# 		# @account = account
	# 		# respond_to do |wants|
	# 		# 	wants.js { render :create_success, layout: false }
	# 		# 	wants.html { render "mercado_pago" }
	# 		# end
	# 	else
	# 		@account = account
	# 		flash[:notice] = "Error na contração de Portfolio"
	# 		respond_to do |wants|
	# 			wants.js { render :create_failure, layout: false }
	# 			wants.html {render :contract }
	# 		end
	# 	end
	# end

	def create
		sign_out if user_signed_in?
		password = Devise.friendly_token.first(6)
		customer_plan_id = params[:customer_plan_id]
		account = @trace.accounts.new(account_params)
		account.state = "enable"
		# account.customer.store = current_store
		account.customer.role = "customer"
		account.customer.role_control = "user"
		account.customer.user.password = password
		account.traces << @trace
		if @trace.valid? and account.save
			# invoice_name = "Trace##{@trace.id}-Account##{account.id}-#{Time.zone.now.strftime("%Y-%m")}" 
			plan_usage = account.add_account_trace_to_planusage(@trace, customer_plan_id)
			customer_plan = plan_usage.usageable
			customer_plan.promotion_use = true if params[:promotion] == "promotion"
			customer_plan.save
			# account.customer.create_invoice_customer(invoice_name)
			# @customer.create_user(email: @customer.user_email, password: password)
			redirect_to finish_dashboard_path(@trace.name, account)
		else
			@account = account
			flash[:notice] = "Error na contração de Portfolio"
			render :contract
		end
	end

	def dashboard_restrict
		flash[:notice] = nil
		unless @trace.nil? and current_store.nil?
			@current_store = @trace.try(:store)
			@current_store ||= current_store
			if @current_store.dashboard_restrict == "enable" and (not user_signed_in? or @current_store.users.find_by(id:current_user.try(:id)).nil?)
				sign_out current_user
				redirect_to user_session_path, notice: "Dashboard restrict. You must be logged"
			else
				@traces = @current_store.traces.active.map do |trace| 
					trace.search_date_begin 				= session[:date_begin].strip().to_datetime.change(offset: @timezone) 
					trace.search_date_end 					= session[:date_end].strip().to_datetime.change(offset: @timezone) 
					# trace.dashboard_magic_number 	  = trace.magic_number_restrict?


					[trace.profit_masters.to_f, trace.id]
				end
				@traces = @traces.sort
			end
		else
			redirect_to root_path, notice: "Dashboard not found"
		end
	end

	def index
		@all_records = request.fullpath.include?("all") ? true : false
		respond_to do |wants|
			
			wants.html { render :index}
		end
	end

	def show
		@trace.search_date_begin 				= session[:date_begin].strip().to_datetime.change(offset: @timezone) 
		@trace.search_date_end 					= session[:date_end].strip().to_datetime.change(offset: @timezone) 
		# @trace.dashboard_magic_number 	= session[:dashboard_magic_number]

		respond_to do |wants|
			wants.html do
				if @trace
					render action: :show
				else
					redirect_to dashboards_path, layout: 'modernize'
				end
			end
		end
	end

	def account
		@trace = Trace.find_by(name: params[:name])
		# @account = current_store.accounts.find(params[:id])
    @account.search_date_begin = session[:date_begin].strip().to_datetime.change(offset: @timezone) 
    @account.search_date_end = session[:date_end].strip().to_datetime.change(offset: @timezone) 

		# @trace = @account.traces.find(params[:trace_id])
		respond_to do |wants|
			wants.html do
				if @account
					render action: :account
				else
					redirect_to dashboards_path
				end
			end
		end
	end

	private

	def account_params
	  params.require(:account).permit(:name, :url, :password, :email, :kind, :meta_margin_mode, :meta_mode, :store_id, settings:[:contract_volume],
	  						customer_attributes:[:name, :customer_plan_id, :user_email, :store_id, user_attributes:[:email, :store_id]]) 
	end

	def set_trace
		@trace = Trace.find_by(name: params[:name])
		unless @trace.nil?
		else
			redirect_to root_path, notice: "Dashboard Not found"
		end
	end

	def set_account
		if current_store == Store.first
			@account = Account.find(params[:id])
		else
			@account = current_store.accounts.find(params[:id])
		end	
	end

	def filters
		# if params[:datefilter].present?
		# session[:dashboard_magic_number] = params[:dashboard_magic_number].present? ? true : false

		date_today = Date.today
		# dates = "#{date_today} - #{date_today}"
		@timezone = params[:timezone].present? ? params[:timezone] : Time.zone.formatted_offset
		# session[:dates] = params[:datefilter]
		if params[:datefilter].blank?# and session[:date_begin].nil? and session[:date_end].nil?
			dates = "#{(date_today.beginning_of_month).strftime('%d/%m/%Y')} - #{date_today.end_of_month.strftime('%d/%m/%Y')}"
			session[:dates] = dates
			session[:date_begin] = dates.split("-")[0]
			session[:date_end] = dates.split("-")[1]					

		else
			if params[:datefilter].present? 
				dates = params[:datefilter].split("-")
				if dates[0] != session[:date_begin] or dates[1] != session[:date_end]
					session[:dates] = params[:datefilter]
					session[:date_begin] = dates[0]
					session[:date_end] = dates[1]					
				end
			else
				session[:dates] = "#{session[:date_begin]} - #{session[:date_end]}"
			end
		end
	end


end