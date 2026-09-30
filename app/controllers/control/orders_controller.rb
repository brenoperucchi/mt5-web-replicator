module Control
  class OrdersController < Control::BaseController
    prepend AdministrateRansack::Searchable

    def show_search_bar?
      false
    end

    def new_resource
      Order.new
    end
  end
end
