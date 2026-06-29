class TransactionPolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.all
    end

    def resolve_admin
      scope.where(owner: user)
    end
  end

  def index?
    @user.userable.role == "customer" or @user.userable.role == "administrator" 
  end

  def edit?
    @user.userable.role == "customer" or @user.userable.role == "administrator" 
  end

  def update?
    @user.userable.role == "customer" or @user.userable.role == "administrator" 
  end

  def show?
    @user.userable.role == "customer" or @user.userable.role == "administrator" 
  end
  
  def new?
    @user.userable.role == "customer" or @user.userable.role == "administrator" 
  end

end
