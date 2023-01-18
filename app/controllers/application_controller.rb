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
			flash[:notice] = I18n.t(:after_sign_error, scope: 'helpers.controller.app_controller') unless user_signed_in? 
			sign_out(resource)
			new_user_session_path
		end	  
	end

  private

  def set_current_user
    Current.user = current_user
  end

end
