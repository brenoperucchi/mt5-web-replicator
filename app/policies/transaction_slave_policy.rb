class TransactionSlavePolicy < ApplicationPolicy
  class Scope < Scope
    def resolve
      scope.all
    end

    def resolve_admin
      scope.where(owner: user)
    end
  end

  def index?
    @user.userable.role == "customer" or @user.userable.role == "admin" 
  end

  def edit?
    @user.userable.role == "customer" or @user.userable.role == "admin" 
  end

  def update?
    @user.userable.role == "customer" or @user.userable.role == "admin" 
  end

  def show?
    @user.userable.role == "customer" or @user.userable.role == "admin" 
  end
  
  def new?
    @user.userable.role == "customer" or @user.userable.role == "admin" 
  end

end
