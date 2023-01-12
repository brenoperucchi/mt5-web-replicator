require "sentient_store"

module Control
  class BaseController < Admin::ApplicationController
    include SentientStore
    include Administrate::Punditize

    rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized


    def create
      resource = current_user.store.try(resource_name.to_s.pluralize.to_sym).try(:new, (resource_params))
      authorize_resource(resource)

      if resource.save
        redirect_to(
          after_resource_created_path(resource),
          notice: translate_with_resource("create.success"),
        )
      else
        render :new, locals: {
          page: Administrate::Page::Form.new(dashboard, resource),
        }, status: :unprocessable_entity
      end
    end

    def destroy
      sdsds
      if requested_resource.soft_destroy
        flash[:notice] = translate_with_resource("destroy.success")
      else
        flash[:error] = requested_resource.errors.full_messages.join("<br/>")
      end
      redirect_to after_resource_destroyed_path(requested_resource)
    end
    private

    def user_not_authorized
      flash[:alert] = "You are not authorized to perform this action."
      redirect_back(fallback_location: user_session_path)
    end


    def new_resource
      current_store.try(resource_name.to_s.pluralize.to_sym).try(:new)
    end

    def dashboard
      @dashboard ||= "#{namespace}::#{resource_name.to_s.classify}Dashboard".try(:classify).try(:constantize).try(:new)
      # @dashboard ||= Control::AccountDashboard.new
    end

    def scoped_resource
      current_user.store.send("#{resource_name}".pluralize)
    end

  end
end