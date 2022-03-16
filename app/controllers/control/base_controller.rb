module Control
  class BaseController < Admin::ApplicationController
    
    def new_resource
      current_user.store.try(resource_name.to_s.pluralize.to_sym).try(:new)
    end


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

  end
end