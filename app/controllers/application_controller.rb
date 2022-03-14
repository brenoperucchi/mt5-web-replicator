class ApplicationController < ActionController::Base
	protect_from_forgery with: :null_session
  # protect_from_forgery with: :exception

	# layout "application"

	def after_sign_in_path_for(resource)
		if resource.userable.role.downcase == "admin"	  
			admin_customers_path
		else
			control_accounts_path
		end
	  # user_path(current_user) # your path
	end

end
