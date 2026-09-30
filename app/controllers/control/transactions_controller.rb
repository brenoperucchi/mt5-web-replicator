module Control
  class TransactionsController < Control::BaseController
    def new_resource
      Transaction.new
    end

    def find_resource(param)
      Transaction.find_by!(id: param)
    end
  end
end
