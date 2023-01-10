require "sentient_store"

class ApplicationController < ActionController::Base
	include SentientStore
	protect_from_forgery with: :null_session
	# include SentientStoreController
	before_action :current_store
	helper_method :current_store
	before_action :set_current_user

  # protect_from_forgery with: :exception

	# layout "application"

	def after_sign_in_path_for(resource)
		if resource.userable.try(:administrator?)
			admin_customers_path
		elsif resource.userable.try(:customer?)
			control_accounts_path
		else
			flash[:notice] = "Error Login #001"
			sign_out(resource)
			new_user_session_path
		end	  
	end

  private

  def set_current_user
    Current.user = current_user
  end

end
