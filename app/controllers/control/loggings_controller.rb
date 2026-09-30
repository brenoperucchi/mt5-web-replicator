module Control
  class LoggingsController < Control::BaseController
    def scoped_resource
      Logging
    end
  end
end