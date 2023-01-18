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

    self.resource = resource_class.new(sign_in_params)
    # super
  end

  # POST /resource/sign_in
  # def create
  #   super
  # end

  def create
    # self.resource = warden.authenticate!
    self.resource = User.where(email: sign_in_params["email"]).take
    if warden.authenticated?
      sign_in(resource)
      set_flash_message!(:notice, :signed_in)
      respond_with resource, location: after_sign_in_path_for(resource)
    else
      if !resource
        flash[:notice] = "*** Login Failure: bad email address given: #{sign_in_params["email"]}"
      else
        flash[:notice] = "*** Login Failure: password mismatch for: #{sign_in_params["email"]}"
      end
      self.resource ||= resource_class.new
      # render :new
      redirect_to user_session_url(email: sign_in_params["email"])
    end
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
