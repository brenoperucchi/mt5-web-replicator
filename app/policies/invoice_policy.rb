class InvoicePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.all
    end

    def resolve_admin
      scope.where(owner: user)
    end
  end

  def index?
    @user.userable.role == "customer"
  end

  def edit?
    @user.userable.role == "customer"
  end

  def update?
    @user.userable.role == "customer"
  end

  def show?
    @user.userable.role == "customer"
  end

end
