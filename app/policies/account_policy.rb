class AccountPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.all
    end

    def resolve_admin
      scope.where(owner: user)
    end
  end

  def destroy?
    @user.userable.role == "administrator" or @user.userable.role_control == "owner"
  end

end