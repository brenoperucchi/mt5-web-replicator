module Control
  class InvoicesController < Control::BaseController
    def new_resource
      resource_name.to_s.pluralize.to_sym.try(:new)
    end

    def dashboard
      @dashboard ||= Control::InvoiceDashboard.new
    end

    def scoped_resource
      current_user.store.sinvoices
    end
  end
end
