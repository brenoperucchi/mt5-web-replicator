module Panel
  class InvoicesController < Panel::BaseController
    before_action :authenticate_user!

    layout 'panel'

    def index

      @customer = current_user.userable
      @invoices = @customer.invoices
    end

    def invoice_send
      # Scope to the signed-in customer: never start checkout on someone else's invoice.
      @invoice = current_user.userable.invoices.find(params[:id])
      if @invoice.invoice_send
        # payment_link is the Stripe Checkout URL we created server-side (external host).
        redirect_to @invoice.payment_link, notice: "Invoice Sended!", allow_other_host: true
      else
        redirect_to panel_invoices_path, :alert => "Invoice Not Sended!"
      end
    end

    def item_conciliated
      # Scope to the signed-in customer's invoice: never expose another customer's orders.
      item = current_user.userable.invoices.find(params[:id]).items.find(params[:item_id])
      if item && item.loggings.where(state: "CONCILIATE").present?
        
        logging = item.loggings.where(state: "CONCILIATE").last

        @presenter = API::V2::APISlaveOrdersHistoryPresenter.new(logging.content)
        @item_conciliated = @presenter&.orders
        @item_conciliated = @item_conciliated if @item_conciliated.present?
      end
      @item_conciliated ||= []
    end
  end
end
