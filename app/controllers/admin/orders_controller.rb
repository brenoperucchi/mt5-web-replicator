module Admin
  class OrdersController < Admin::BaseController
    prepend AdministrateRansack::Searchable

    def show_search_bar?
      false
    end

    def scoped_resource
        resource_class.order('id desc')
    end
  end
end
