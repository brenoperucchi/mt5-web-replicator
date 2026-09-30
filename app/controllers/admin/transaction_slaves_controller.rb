module Admin
  class TransactionSlavesController < Admin::BaseController
    prepend AdministrateRansack::Searchable

    def show_search_bar?
      false
    end
  end
end
