module Panel
  class DashboardController < Panel::BaseController
    before_action :authenticate_user!

    layout 'panel'

    def index
    end
  end
end
