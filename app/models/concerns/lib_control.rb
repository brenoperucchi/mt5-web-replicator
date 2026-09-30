module LibControl
  extend ActiveSupport::Concern

  included do
		after_create :register_resource_plan

		def soft_destroy
		  self.plan_usages.where(disable_at:nil).update_all(disable_at:DateTime.current) if self.respond_to?(:plan_usages)
      self.soft_destroy_custom if self.respond_to?(:soft_destroy_custom)
		  self.update(deleted_at: DateTime.current) if self.respond_to?(:deleted_at)
		end

		def soft_restore
		  self.update(deleted_at: nil) if self.respond_to?(:deleted_at)
		end

		def register_resource_plan
      if self.respond_to?(:plan_usages)
        named = self.respond_to?(:kind) ? self.kind : self.class.name.capitalize 
	  	  store.register_resources_usages(self, named)
      end
		end

	end

end