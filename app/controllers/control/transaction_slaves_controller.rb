module Control
  class TransactionSlavesController < Control::BaseController
    def new_resource
      TransactionSlave.new
    end

    def dashboard
      @dashboard ||= Control::TransactionSlaveDashboard.new
    end

    def scoped_resource
      TransactionSlave.where(store_id:current_user.store)
    end
  end
end
