class PagesController < ApplicationController
	# skip_before_action :after_sign_in_path_for
	# layout 'stisla'
  layout 'tailwind_layout2'

	before_action :sign_up!


	def sign_up!
		redirect_to new_user_session_path if !user_signed_in?
			
	end

	def index
		respond_to do |wants|
			wants.html do 
				@executed = current_user.userable.store.transactions.executed
				@traces = current_user.userable.store.traces.active

			end
		end
	end

end
