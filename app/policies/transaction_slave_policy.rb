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
    @user.userable.role == "administrator" or @user.userable.role_control == "admin" 
  end

  def edit?
    @user.userable.role == "administrator" or @user.userable.role_control == "admin" 
  end

  def update?
    @user.userable.role == "administrator" or @user.userable.role_control == "admin" 
  end

  def show?
    @user.userable.role == "administrator" or @user.userable.role_control == "admin" 
  end
  
  def new?
    @user.userable.role == "administrator" or @user.userable.role_control == "admin" 
  end

  def destroy?
    @user.userable.role == "administrator" or @user.userable.role_control == "admin" 
  end

end
