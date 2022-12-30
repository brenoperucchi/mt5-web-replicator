require "administrate/field/associative.rb"
require "administrate/field/belongs_to"
require "sentient_store.rb"

module Fields
	class BelongsToField < Administrate::Field::BelongsTo
		include SentientStore

		def scoped
		  options.key?(:scoped) ? options[:scoped] : :all
		end

		private 

		def candidate_resources
			if resource.respond_to?(:store)
				resource.store.send(associated_class.name.pluralize.downcase.to_sym).send(scoped)
			else
				# scope = options[:scope] ? options[:scope].call : current_store_field.send(associated_class.name.pluralize.downcase.to_sym).send(scoped)
				resource.send(associated_class.name.pluralize.downcase.to_sym).send(scoped)
		  end

		  # order = options.delete(:order)
		  # order ? scope.reorder(order) : scope
		end

	end
end