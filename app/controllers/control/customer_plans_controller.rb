module Control
  class CustomerPlansController < Control::BaseController
    def dashboard
      @dashboard ||= Control::CustomerPlanDashboard.new
    end

    def scoped_resource
      current_user.store.customer_plans
    end
  end
end
