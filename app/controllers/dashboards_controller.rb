class DashboardsController < ApplicationController
	# skip_before_action :after_sign_in_path_for
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
				@traces = Store.first.traces.active
				# @traces = current_user.userable.store.traces.active
			end
		end
	end

	def show
		@trace = Trace.find(params[:id])
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
		@account = Account.find(params[:id])
		@trace = Trace.find(params[:trace_id])
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

end
