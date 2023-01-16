# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  layout "saasley"

  # def auth_options
  #   { scope: resource_name } #, recall: "new" }
  # end

  # before_action :configure_sign_in_params, only: [:create]

  # GET /resource/sign_in
  # def new
  #   super
  # end
  def new
    flash[:notice] = nil
    self.resource = resource_class.new(sign_in_params)
    # super
  end


  # POST /resource/sign_in
  # def create
  #   super
  # end
  # POST /resource/sign_in
  def create
    # self.resource = warden.authenticate!
    # self.resource = resource_class.new(sign_in_params)
    self.resource = User.where(email: sign_in_params["email"]).take
    # resource.store = Store.first
    if warden.authenticated?
      sign_in(resource)
      set_flash_message!(:notice, :signed_in)
      # yield resource if block_given?
      # redirect_to admin_store_path, notice: I18n.t(:signed_in, scope: 'devise.sessions')
      respond_with resource, location: after_sign_in_path_for(resource)
    else
      # "unauthenticated" indicates a login failure
      if !resource
        flash[:notice] = "*** Login Failure: bad email address given: #{sign_in_params["email"]}"
      else
        flash[:notice] = "*** Login Failure: password mismatch for: #{sign_in_params["email"]}"
      end
      self.resource ||= resource_class.new
      render :new
    end

    # # email = params[:user][:email]
    # @resource = resource_class.new(sign_in_params)
    # # @resource.validate_off = true
    # # referer = stored_location_for(resource) || request.referer || root_path
    # # user = User.where(email: email , store: current_store).take
    # if not @resource.valid?
    #   render :new
    # # elsif user.nil?
    # #   redirect_to(new_public_broker_path(email: email), alert: I18n.t(:unauthenticated_email, scope: 'devise.failure')) 
    # # elsif user.userable.admin?
    # #   redirect_to admin_new_session_path, alert: I18n.t(:unauthenticated, scope: 'devise.failure')
    # else
    #   sign_in user
    #   redirect_to admin_store_path, notice: I18n.t(:signed_in, scope: 'devise.sessions')
    # end
    # # super
  end


  # DELETE /resource/sign_out
  # def destroy
  #   super
  # end

  # protected

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_in_params
  #   devise_parameter_sanitizer.permit(:sign_in, keys: [:attribute])
  # end
end
