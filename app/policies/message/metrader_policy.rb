module Message
  class Metatrader < ApplicationPolicy
    class Scope < Scope
      def resolve
        scope.all
      end

      def resolve_admin
        binding.pry
        scope.where(owner: user)
      end
    end

    def index?
      binding.pry
      @user.userable.role == "customer" or @user.userable.role == "admin" 
    end

    def edit?
      binding.pry
      @user.userable.role == "customer" or @user.userable.role == "admin" 
    end

    def update?
      binding.pry
      @user.userable.role == "customer" or @user.userable.role == "admin" 
    end

    def show?
      binding.pry
      @user.userable.role == "customer" or @user.userable.role == "admin" 
    end
    
    def new?
      binding.pry
      @user.userable.role == "customer" or @user.userable.role == "admin" 
    end

  end
end