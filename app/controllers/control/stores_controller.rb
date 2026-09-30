module Control
  class Control::StoresController < Control::BaseController
    def files
      @url = current_store.language == "pt-BR" ? "https://imentore.freshdesk.com/support/solutions/articles/151000020358" : "https://imentore.freshdesk.com/support/solutions/articles/151000203441"
    end

    def dashboard
      @dashboard ||= Control::StoreDashboard.new
    end

    def scoped_resource
      Store.where(id:current_user.store)
    end
  end
end
