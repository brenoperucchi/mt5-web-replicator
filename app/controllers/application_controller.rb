class ApplicationController < ActionController::Base
	protect_from_forgery with: :null_session
	# include SentientStoreController
	before_action :current_store
	helper_method :current_store

	def current_store
	  subdomain = request.subdomain.split('.').try(:first)
	  Rails.logger.info("SUB DOMAIN #{request.subdomain}")
	  Rails.logger.info("SUB DOMAIN SPLIT #{subdomain}")
	  session[:store_id] = Store.find_by(url: subdomain) || Store.first   
	  Store.current = session[:store_id]
	end

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
