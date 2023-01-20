module LibControl
  extend ActiveSupport::Concern

  included do
		after_create :register_resource_plan

		def soft_destroy
		  self.plan_usages.where(disable_at:nil).update_all(disable_at:DateTime.now)
		  self.update(deleted_at: DateTime.now)
		end

		def soft_restore
		  self.update(deleted_at: nil)
		end

		def register_resource_plan
			named = self.respond_to?(:kind) ? self.kind : self.class.name.capitalize
	  	store.register_resources_usages(self, named)
		end

	end


  # def self.included(base)
  #   base.send :extend, ClassMethods
  # end

  # module ClassMethods
	# 	send :include, InstanceMethods
	# 	after_create :register_resource_plan
  # end

  # module InstanceMethods
  # 	def soft_destroy
  # 	  self.plan_usage.update(disable_at:DateTime.now) if self.plan_usage
  # 	  self.update(deleted_at: DateTime.now)
  # 	  self.remove_resource_plan
  # 	end

  # 	def soft_restore
  # 	  self.update(deleted_at: nil)
  # 	end

  # 	def register_resource_plan
  # 	  store.register_resource_plan(self, self.kind)
  # 	end

  # 	def remove_resource_plan
  # 	  store.register_resource_plan(self, self.kind)
  # 	end

  # end

end