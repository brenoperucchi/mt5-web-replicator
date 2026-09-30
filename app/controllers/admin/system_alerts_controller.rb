module Admin
  class SystemAlertsController < Admin::BaseController
    prepend AdministrateRansack::Searchable

    def show_search_bar?
      true
    end

    def form_advanced
      true      
    end
  end
end
