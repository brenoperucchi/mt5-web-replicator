module PaperTrail
  class VersionPolicy < ApplicationPolicy
    class Scope < Scope
      def resolve
        scope.all
      end

      def resolve_admin
        scope.where(owner: user)
      end
    end

    def index?
      false
    end

    def show?
      true
    end

    def destroy?
      false
    end

  end
end