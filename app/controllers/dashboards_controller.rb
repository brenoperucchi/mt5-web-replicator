class DashboardsController < ApplicationController
	# skip_before_action :after_sign_in_path_for
	before_action :set_account, only:[:account]
	before_action :set_trace, except: [:index, :account]
	before_action :filters#, except: :index
	before_action :dashboard_restrict

	# before_action :authenticate_user
	# layout 'stisla'
  layout 'mintone'

	# before_action :sign_up!


	# def sign_up!
	# 	redirect_to new_user_session_path if !user_signed_in?
			
	# end

	def dashboard_restrict
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
					redirect_to dashboards_path
				end
			end
		end
	end

	def account
		@trace = Trace.find_by(id:params[:trace_id])
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

	def set_trace
		@trace = Trace.find_by(id:params[:id])
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
		if params[:datefilter].blank? and session[:date_begin].nil? and session[:date_end].nil?
			dates = "#{(date_today - 1.month).strftime('%d/%m/%Y')} - #{date_today.strftime('%d/%m/%Y')}"
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