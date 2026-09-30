# frozen_string_literal: true

class Users::SessionsController < Devise::SessionsController
  prepend_before_action :check_captcha, only: [:create]

  layout "saasley"

  # GET /resource/sign_in
  # def new
  #   super
  # end
  def new

    self.resource = resource_class.new(sign_in_params)
  end

  # POST /resource/sign_in
  # def create
  #   super
  # end

  def create
    self.resource = User.where(email: sign_in_params["email"]).take
    if warden.authenticated?
      sign_in(resource)
      set_flash_message!(:notice, :signed_in)
      respond_with resource, location: after_sign_in_path_for(resource)
    else
      if !resource
        flash[:notice] = I18n.t(:bad_login_email, scope: 'helpers.controller.session', email: sign_in_params["email"])
      else
        flash[:notice] = I18n.t(:bad_login_password, scope: 'helpers.controller.session', email: sign_in_params["email"])
      end
      self.resource ||= resource_class.new
      redirect_to user_session_url(email: sign_in_params["email"])
    end
  end

  # DELETE /resource/sign_out
  # def destroy
  #   super
  # end

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_in_params
  #   devise_parameter_sanitizer.permit(:sign_in, keys: [:attribute])
  # end
  private

  def check_captcha
  end

  def alert_recaptcha
    self.resource = resource_class.new sign_in_params
    respond_with_navigational(resource) { render :new }
  end
end
