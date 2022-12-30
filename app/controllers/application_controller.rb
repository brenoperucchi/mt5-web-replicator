require "sentient_store"

class ApplicationController < ActionController::Base
	include SentientStore
	protect_from_forgery with: :null_session
	# include SentientStoreController
	before_action :current_store
	helper_method :current_store

  # protect_from_forgery with: :exception

	# layout "application"

	def after_sign_in_path_for(resource)
		case resource.userable.role.try(:downcase)
		when "admin"
			admin_customers_path
		when "customer"
			control_accounts_path
		else
			flash[:notice] = "Login error role"
			sign_out(resource)
			new_user_session_path
		end	  
	end

end
