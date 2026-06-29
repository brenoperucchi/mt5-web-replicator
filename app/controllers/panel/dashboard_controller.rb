module Panel
  class DashboardController < Panel::BaseController
    before_action :authenticate_user!, except: [:back_url]

    layout 'panel'

    def index
    end

    def back_url
      @params = {payment_id: params[:payment_id], status: params[:status], external_reference: params[:external_reference], merchant_order_id: params[:merchant_order_id]}
      @invoice = Invoice.find(params[:invoice_id])
      @invoice.payment_method.check_payment_get(params[:payment_id])

      respond_to do |wants|
        wants.html { render :back_url }
      end

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
