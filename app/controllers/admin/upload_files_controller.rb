module Admin
  class UploadFilesController < Admin::BaseController
    def show_search_bar?
      false
    end

    def permitted_attributes
      super + [:file => []]
    end
  end
end
