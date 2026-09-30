module Control
  class InstrumentsController < Control::BaseController
    def dashboard
      @dashboard ||= Control::InstrumentDashboard.new
    end

    def scoped_resource
      current_user.store.instruments
    end
  end
end
