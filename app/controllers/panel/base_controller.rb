require "sentient_store"

module Panel
  class BaseController < ApplicationController
    include SentientStore


    def authenticate_user!
      redirect_to new_panel_user_session_path, notice: I18n.t(:must_be_logged, scope: 'helpers.controller.app_controller.admin') unless user_signed_in?
    end

  end
end