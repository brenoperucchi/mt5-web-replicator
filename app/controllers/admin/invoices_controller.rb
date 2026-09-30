module Admin
  class InvoicesController < Admin::BaseController
    def invoice_send
      if requested_resource.invoice_send
        redirect_to admin_invoices_path, :notice => "Invoice Sended!"
      else
        redirect_to admin_invoices_path, :alert => "Invoice Not Sended!"
      end
    end
  end
end
