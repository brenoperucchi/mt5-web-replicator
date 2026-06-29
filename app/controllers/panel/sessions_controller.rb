# frozen_string_literal: true
module Panel
  class SessionsController < Devise::SessionsController
    protect_from_forgery except: :destroy
    # prepend_before_action :check_captcha, only: [:create]

    layout "panel"

    # def auth_options
    #   { scope: resource_name } #, recall: "new" }
    # end

    # before_action :configure_sign_in_params, only: [:create]

    # GET /resource/sign_in
    # def new
    #   super
    # end
    def new
      self.resource = resource_class.new
      # super
    end

    # POST /resource/sign_in
    # def create
    #   super
    # end

    # def create
    #   # self.resource = warden.authenticate!
    #   # Customer.where()

    #   if warden.authenticated?
    #     sign_in(resource)
    #     set_flash_message!(:notice, :signed_in)
    #     respond_with resource, location: after_sign_in_path_for(resource)
    #   else
    #     if !resource
    #       flash[:notice] = I18n.t(:bad_account_email, scope: 'helpers.controller.session', email: sign_in_params["email"])
    #     else
    #       flash[:notice] = I18n.t(:bad_account_password, scope: 'helpers.controller.session', email: sign_in_params["email"])
    #     end
    #     self.resource ||= resource_class.new
    #     render :new
    #     # redirect_to control_new_session_path(metatrader_account: sign_in_params["metatrader_account"])
    #   end
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

    # protected

    # If you have extra params to permit, append them to the sanitizer.
    # def configure_sign_in_params
    #   devise_parameter_sanitizer.permit(:sign_in, keys: [:attribute])
    # end
    private

    def configure_sign_in_params
      devise_parameter_sanitizer.permit(:sign_in, keys: [:metatrader_account, :password, :remember_me])
    end

    def check_account
      # if current_store
        @account = Account.find_by(name: params[:user]["metatrader_account"])
        self.resource = @account.try(:customer).try(:user)
      # end
    end

    def sign_in_params
      {"email" => check_account.email, "password" => params[:user][:password], "remember_me" => params[:user][:remember_me]}
      # params.require(:user).permit(:metatrader_account, :password, :remember_me) 
    end

    def check_captcha
      # if Rails.env.production?
      #   alert_recaptcha unless verify_recaptcha 
      # end
    end

    def alert_recaptcha
      self.resource = resource_class.new sign_in_params
      respond_with_navigational(resource) { render :new }
    end
  end
end