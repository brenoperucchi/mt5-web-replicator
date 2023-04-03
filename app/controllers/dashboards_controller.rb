class DashboardsController < ApplicationController
	# skip_before_action :after_sign_in_path_for
	before_action :filter_date
	before_action :set_trace, 	only:[:show]
	before_action :set_account, only:[:account]

	# before_action :authenticate_user
	# layout 'stisla'
  layout 'mintone'

	# before_action :sign_up!


	# def sign_up!
	# 	redirect_to new_user_session_path if !user_signed_in?
			
	# end

	def index
		respond_to do |wants|
			wants.html do 
				unless current_store.nil?
					if current_store.dashboard_restrict == "enable" and not user_signed_in?
						flash[:notice] = 'do_you_must_be_login'
						redirect_to user_session_path
					else
						@traces = current_store.traces.active
					end
				else
					redirect_to root_path
				end
			end
		end
	end

	def show
		@trace.search_date_begin = session[:date_begin].strip().to_datetime.change(offset: @timezone) 
		@trace.search_date_end = session[:date_end].strip().to_datetime.change(offset: @timezone) 

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
		# @account = current_store.accounts.find(params[:id])
    @account.search_date_begin = session[:date_begin].strip().to_datetime.change(offset: @timezone) 
    @account.search_date_end = session[:date_end].strip().to_datetime.change(offset: @timezone) 

		@trace = @account.traces.find(params[:trace_id])
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

	def set_locale
		if current_store.nil?
			I18n.locale = 'en'
		else
			I18n.locale = current_store.language
		end
	end


	def set_trace
		if current_store == Store.first
			@trace = Trace.find(params[:id])
		else
			@trace = current_store.traces.find(params[:id])
		end
		
	end

	def set_account
		if current_store == Store.first
			@account = Account.find(params[:id])
		else
			@account = current_store.accounts.find(params[:id])
		end
		
	end

	def filter_date
		# if params[:datefilter].present?
		date_today = Date.today
		# dates = "#{date_today} - #{date_today}"
		@timezone = params[:timezone].present? ? params[:timezone] : Time.zone.formatted_offset
		# session[:dates] = params[:datefilter]
		if params[:datefilter].blank? and session[:date_begin].nil? and session[:date_end].nil?
			dates = "#{date_today.strftime('%d/%m/%Y')} - #{date_today.strftime('%d/%m/%Y')}"
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
