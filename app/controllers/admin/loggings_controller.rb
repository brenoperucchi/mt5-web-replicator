module Admin
  class LoggingsController < Admin::BaseController
    prepend AdministrateRansack::Searchable

    def show_search_bar?
      false
    end
  end
end
