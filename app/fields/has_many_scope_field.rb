require "administrate/field/associative.rb"
require "administrate/page/collection"
require "administrate/order"
require "sentient_store.rb"

module Fields
  class HasManyScopeField < Administrate::Field::HasMany

    def to_s
      data
    end

    def scoped
      options.key?(:scoped) ? options[:scoped] : :all
    end


    def associated_resource_options
      candidate_resources.map do |resource|
        [display_candidate_resource(resource), resource.send(primary_key)]
      end
    end

    def order_from_params(params)
      Administrate::Order.new(
        params.fetch(:order, sort_by),
        params.fetch(:direction, direction),
      )
    end

    def order
      @order ||= Administrate::Order.new(sort_by, direction)
    end

    # def resources(page = 1, order = self.order, current_user = nil)
    #   resources = order.apply(data(current_user)).page(page).per(limit)
    #   includes.any? ? resources.includes(*includes) : resources
    # end


    def data(current_user=nil)
      if options.key?(:associated)
        if resource.respond_to?(:store)
          @data ||= resource.store.send(associated_class.name.pluralize.downcase.to_sym).send(scoped)
        else
          if resource.respond_to?(scoped)
            resource.send(associated_class.name.pluralize.downcase.to_sym).send(scoped)
          else
            resource.send(associated_class.name.pluralize.downcase.to_sym)
          end
        end
      else
        @data = resource.send(associated_class.name.pluralize.downcase.to_sym)
        @data = @data.send(scoped) if @data.respond_to?(scoped)
        @data
      end
    end

    private

    def includes
      associated_dashboard.collection_includes
    end

    def candidate_resources
      if options.key?(:associated)
        if resource.respond_to?(:store)
          resource.store.send(associated_class.name.pluralize.downcase.to_sym).send(scoped)
        else
          if resource.respond_to?(scoped)
            resource.send(associated_class.name.pluralize.downcase.to_sym).send(scoped)
          else
            resource.send(associated_class.name.pluralize.downcase.to_sym)
          end
        end
        # current_store_field.send(associated_class.name.pluralize.downcase.to_sym).send(scoped)
      elsif options.key?(:scoped)
        resource.send(associated_class.name.pluralize.downcase.to_sym).send(scoped)
      elsif options.key?(:includes)
        includes = options.fetch(:includes)
        associated_class.includes(*includes).all
      else
        associated_class.all
      end
    end

    def display_candidate_resource(resource)
      associated_dashboard.display_resource(resource)
    end

  end
end