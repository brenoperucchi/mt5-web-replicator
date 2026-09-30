# frozen_string_literal: true
module Panel
  class SessionsController < Devise::SessionsController
    protect_from_forgery except: :destroy

    layout "panel"

    # GET /resource/sign_in
    # def new
    #   super
    # end
    def new
      self.resource = resource_class.new
    end

    # POST /resource/sign_in
    # def create
    #   super
    # end

    def create
      self.resource = check_account
      if self.resource && self.resource.valid_password?(sign_in_params["password"])
        sign_in(resource)
        set_flash_message!(:notice, :signed_in)
        respond_with resource, location: panel_dashboard_index_path(@account)
      else
        # Configurações para falha de login
        prepare_and_render_new_session
      end
    end

    def prepare_and_render_new_session
      set_flash_message!(:notice, :invalid)
      self.resource ||= resource_class.new
      render :new, status: :unprocessable_entity
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

    def configure_sign_in_params
      devise_parameter_sanitizer.permit(:sign_in, keys: [:metatrader_account, :password, :remember_me])
    end

    def check_account
        @account = Account.find_by(name: params[:user]["metatrader_account"])
        self.resource = @account.try(:customer).try(:user)
    end

    def sign_in_params
      {"email" => check_account.email, "password" => params[:user][:password], "remember_me" => params[:user][:remember_me]}
    end

    def check_captcha
    end

    def alert_recaptcha
      self.resource = resource_class.new sign_in_params
      respond_with_navigational(resource) { render :new }
    end
  end
end