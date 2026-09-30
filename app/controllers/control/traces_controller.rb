module Control
  class TracesController < Control::BaseController
    def find_resource(param)
      Trace.find_by!(id: param)
    end

    def dashboard
      @dashboard ||= Control::TraceDashboard.new
    end

    def scoped_resource
      current_user.store.traces.not_deleted
    end
  end
end
