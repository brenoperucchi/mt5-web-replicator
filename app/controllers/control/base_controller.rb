
module Control
  class BaseController < Admin::ApplicationController

    before_action :current_store
    helper_method :current_store

    def current_store
      subdomain = request.subdomain.split('.')
      session[:store_id] = Store.find_by(url: subdomain) || Store.first   
      Store.current = session[:store_id]
    end

    
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

    def dashboard
      @dashboard ||= "#{namespace}::#{resource_name.to_s.classify}Dashboard".try(:classify).try(:constantize).try(:new)
      # @dashboard ||= Control::AccountDashboard.new
    end

    def scoped_resource
      current_user.store.send("#{resource_name}".pluralize)
    end


  end
end