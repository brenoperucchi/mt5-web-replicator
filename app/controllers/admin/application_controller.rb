require 'base'

# All Administrate controllers inherit from this
# `Administrate::ApplicationController`, making it the ideal place to put
# authentication logic or other before_actions.
#
# If you want to add pagination or other controller-level concerns,
# you're free to overwrite the RESTful controller actions.
module Admin
  class ApplicationController < Administrate::ApplicationController
    before_action :authenticate_user!
    # before_action :authenticate_admin
    # before_action :authenticate_user!


    def scoped_resource
        resource_class.order('id desc')
    end

    def authenticate_admin
      # TODO Add authentication logic here.
    end


    def index
      authorize_resource(resource_class)
      search_term = params[:search].to_s.strip
      resources = filter_resources(scoped_resource, search_term: search_term)
      resources = apply_collection_includes(resources)
      # resources = order.apply(resources)
      resources = order.apply(resources).order('id desc')
      resources = resources.page(params[:page]).per(records_per_page)
      page = Administrate::Page::Collection.new(dashboard, order: order)

      render locals: {
        resources: resources,
        search_term: search_term,
        page: page,
        show_search_bar: show_search_bar?,
      }
      # search_term = params[:search].to_s.strip
      # resource_messages = resource_class
      # # resource_messages = resource_class.where(ancestry:nil).order('content_at desc')#.where.not(state:'action')
      # resources = Administrate::Search.new(resource_messages, dashboard_class, search_term).run
      # resources = apply_collection_includes(resources)
      # resources = order.apply(resources).order('id desc')
      # resources = resources.page(params[:page]).per(records_per_page)
      # page = Administrate::Page::Collection.new(dashboard, order: order)

      # render :index, locals: {
      #   resources: resources,
      #   search_term: search_term,
      #   page: page,
      #   show_search_bar: show_search_bar?,
      # }
    end

    def filter_resources(resources, search_term:)
      Administrate::Search.new(
        resources,
        dashboard,
        search_term,
      ).run
    end

    # Override this value to specify the number of elements to display at a time
    # on index pages. Defaults to 20.
    # def records_per_page
    #   params[:per_page] || 20
    # end
  end
end
