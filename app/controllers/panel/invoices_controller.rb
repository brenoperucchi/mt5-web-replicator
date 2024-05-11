module Panel
  class InvoicesController < Panel::BaseController
    before_action :authenticate_user!

    layout 'panel'

    def index
      # @account = Account.find(params[:account_id])

      @customer = current_user.userable
      @invoices = @customer.invoices
    end

    def invoice_send
      @invoice = Invoice.find(params[:id])
      if @invoice.invoice_send
        redirect_to @invoice.payment_link, :notice => "Invoice Sended!"
      else
        redirect_to panel_invoices_path, :alert => "Invoice Not Sended!"
      end
    end

    def conciliate_orders
      @invoice = Invoice.find(params[:id])
      if @invoice && @invoice.loggings.where(state: "CONCILIATE").present?
        
        logging = @invoice.loggings.where(state: "CONCILIATE").last

        @orders_presenter = API::V2::APISlaveOrdersHistoryPresenter.new(logging.content)
        @conciliate_orders = @orders_presenter&.orders
        @conciliate_orders = @conciliate_orders if @conciliate_orders.present?
      end
      @conciliate_orders ||= []
    end
    # For example, you may want to send an email after a foo is updated.
    #
    # def update
    #   super
    #   send_foo_updated_email(requested_resource)
    # end

    # Override this method to specify custom lookup behavior.
    # This will be used to set the resource for the `show`, `edit`, and `update`
    # actions.
    #
    # def find_resource(param)
    #   Foo.find_by!(slug: param)
    # end

    # The result of this lookup will be available as `requested_resource`

    # Override this if you have certain roles that require a subset
    # this will be used to set the records shown on the `index` action.
    #
    # def scoped_resource
    #   current_user.store.customers.not_deleted
    # end
    # # def scoped_resource
    # #   if current_user.super_admin?
    # #     resource_class
    # #   else
    # #     resource_class.with_less_stuff
    # #   end
    # # end


    # def create
    #   resource = current_user.store.try(resource_name.to_s.pluralize.to_sym).try(:new, (resource_params))
    #   resource.user.store = current_store
    #   authorize_resource(resource)

    #   if resource.save
    #     redirect_to(
    #       after_resource_created_path(resource),
    #       notice: translate_with_resource("create.success"),
    #     )
    #   else
    #     render :new, locals: {
    #       page: Administrate::Page::Form.new(dashboard, resource),
    #     }, status: :unprocessable_entity
    #   end
    # end


    # # def new_resource
    # #   current_user.store.try(resource_name.to_s.pluralize.to_sym).try(:new, ({role:'customer', user_ids:current_user.id}))
    # # end

    # # Override `resource_params` if you want to transform the submitted
    # # data before it's persisted. For example, the following would turn all
    # # empty values into nil values. It uses other APIs such as `resource_class`
    # # and `dashboard`:
    # #
    # # def resource_params
    # #   params.require(resource_class.model_name.param_key).
    # #     permit(dashboard.permitted_attributes).
    # #     transform_values { |value| value == "" ? nil : value }
    # # end

    # # See https://administrate-prototype.herokuapp.com/customizing_controller_actions
    # # for more information

  end
end
