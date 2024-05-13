require "sentient_store"

class ApplicationController < ActionController::Base
	include SentientStore
	protect_from_forgery with: :null_session
	# include SentientStoreController
	before_action :current_store
	helper_method :current_store
	before_action :set_current_user
	before_action :set_locale

  # protect_from_forgery with: :exception

	# layout "application"

	def after_sign_in_path_for(resource)
		if resource.userable.try(:administrator?)
			admin_customers_path
		elsif resource.userable.try(:customer?) and (resource.userable.try(:admin?) || resource.userable.try(:owner?))
			control_accounts_path
		elsif resource.userable.try(:customer?) and resource.userable.try(:user?)
			panel_dashboard_index_path
		else
			flash[:notice] = I18n.t(:after_sign_error, scope: 'helpers.controller.app_controller') unless user_signed_in? 
			sign_out(resource)
			new_user_session_path
		end	  
	end

	def after_sign_out_path_for(user)
		flash[:notice] = I18n.t(:after_sign_success, scope: 'helpers.controller.app_controller') unless user_signed_in? 
		if request.url.include?("/panel/logout")
			new_panel_user_session_path
		else
			new_user_session_path
		end	  
	end

  private

  def set_current_user
    Current.user = current_user
  end

  def set_locale
  	locale = params[:locale]
		case locale
		when "en"
			I18n.locale = 'en'
		else
			I18n.locale = 'pt-BR'
		end
		unless locale
			I18n.locale = current_store ? current_store.language : locale 
		end
  end

end