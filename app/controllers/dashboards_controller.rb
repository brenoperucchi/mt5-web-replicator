class DashboardsController < ApplicationController
	# skip_before_action :after_sign_in_path_for
	before_action :filter_date
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
				@traces = current_store.traces.active
				# @traces = current_user.userable.store.traces.active
			end
		end
	end

	def show
		@trace = current_store.traces.find(params[:id])
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
		@account = current_store.accounts.find(params[:id])
    @account.search_date_begin = @date_begin
    @account.search_date_end = @date_end

		@trace = current_store.traces.find(params[:trace_id])
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
