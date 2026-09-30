module Control
  class AccountsController < Control::BaseController
    def scoped_resource
      current_user.store.accounts.not_deleted
    end
  end
end
