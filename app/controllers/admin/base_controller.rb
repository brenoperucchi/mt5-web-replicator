module Admin
  class BaseController < Admin::ApplicationController
    include SentientStore

  	before_action :restrict_not_admin!

  	def restrict_not_admin!
  		if current_user.userable.role != "administrator"
  			redirect_to control_accounts_path, :alert => "Redirect to Control Admin"             
  		end	
  	end
    
    # def new_resource
    #   current_user.store.try(resource_name.to_s.pluralize.to_sym).try(:new)
    # end

    # def create
    #   resource = current_user.store.try(resource_name.to_s.pluralize.to_sym).try(:new, (resource_params))
    #   authorize_resource(resource)

    #   if resource.save
    #     redirect_to(
    #       after_resource_created_path(resource),
    #       notice: translate_with_resource("create.success"),
    #     )
    #   else
    #     render :new, locals: {
    #       page: Administrate::Page::Form.new(dashboard, resource),
    #     }, status: :unprocessable_entity
    #   end
    # end

    def destroy
      if requested_resource.destroy
        flash[:notice] = translate_with_resource("destroy.success")
      else
        flash[:error] = requested_resource.errors.full_messages.join("<br/>")
      end
      redirect_to [namespace, requested_resource, request.query_parameters]
    end

  end
end