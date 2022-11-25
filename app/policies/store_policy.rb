class StorePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      binding.pry
      scope.all
    end

    def resolve_admin
      binding.pry
      scope.where(owner: user)
    end
  end

  def index?
    @user.userable.role == "customer"
  end

  def edit?
    true
  end

  def update?
    edit?
  end

  def show?
    true    
  end

end
