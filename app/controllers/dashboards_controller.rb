class DashboardsController < ApplicationController
	# skip_before_action :after_sign_in_path_for
	before_action :filter_date
	before_action :set_trace, 	only:[:show]
	before_action :set_account, only:[:account]
	# layout 'stisla'
  layout 'mintone'

	# before_action :sign_up!


	# def sign_up!
	# 	redirect_to new_user_session_path if !user_signed_in?
			
	# end

	def index
		respond_to do |wants|
			wants.html do 
				# @executed = Store.first.transactions.executed
				# @executed = current_user.userable.store.transactions.executed
				if current_store.nil? or current_store == Store.first 
					@traces = Trace.all.active
				else
					@traces = current_store.traces.active
				end

				# @traces = current_user.userable.store.traces.active
			end
		end
	end

	def show
		# @trace = current_store.traces.find(params[:id])
		@trace.search_date_begin = @date_begin
		@trace.search_date_end = @date_end


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
    @account.search_date_begin = @date_begin
    @account.search_date_end = @date_end

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
		if params[:datefilter].present?
			@timezone = params[:timezone].present? ? params[:timezone] : Time.zone.formatted_offset
			@dates = params[:datefilter]
			dates = params[:datefilter].split("-")
			@date_begin = dates[0].strip().to_datetime.change(offset: @timezone)
			@date_end = dates[1].strip().to_datetime.change(offset: @timezone)
		end
	end


end
