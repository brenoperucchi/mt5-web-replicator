# frozen_string_literal: true

class Users::RegistrationsController < Devise::RegistrationsController
  layout "saasley"

  # GET /resource/sign_in
  def new
    redirect_to new_store_path
  end

  # POST /resource/sign_in
  # def create
  #   super
  # end

  # DELETE /resource/sign_out
  # def destroy
  #   super
  # end

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_in_params
  #   devise_parameter_sanitizer.permit(:sign_in, keys: [:attribute])
  # end

end