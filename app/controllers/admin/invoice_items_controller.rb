module Admin
  class InvoiceItemsController < Admin::BaseController
    def show_conciliated
      item = InvoiceItem.find(params[:id])
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
