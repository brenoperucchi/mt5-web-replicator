class PagesController < ApplicationController
	layout 'stisla'

	before_action :sign_up!


	def sign_up!
		redirect_to new_user_registration_path if !user_signed_in?
			
	end

	def index
		@executed = Store.first.transactions.executed
		@traces = Store.first.traces.active
	end

end
