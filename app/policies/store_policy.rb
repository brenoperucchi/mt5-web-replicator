class StorePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.all
    end

    def resolve_admin
      scope.where(owner: user)
    end
  end

  def destroy?
    @user.userable.role == "admin"
  end

end
