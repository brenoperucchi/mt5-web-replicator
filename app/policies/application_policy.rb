# frozen_string_literal: true

class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    # @user.userable.role == "administrator" or @user.userable.role_control == "owner" or @user.userable.role_control == "admin"
    true
  end

  def edit?
    index?
  end

  def update?
    index?
  end

  def show?
    index?
  end
  
  def new?
    index?
  end

  def create?
    index?
  end

  def destroy?
    if @user.userable.role == "administrator" or @user.userable.role_control == "owner"
      true
    else
      false
    end
  end

  class Scope
    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "You must define #resolve in #{self.class}"
    end

    private

    attr_reader :user, :scope
  end
end
