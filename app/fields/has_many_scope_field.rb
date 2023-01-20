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


    def resources(page = 1, order = self.order)
      resources = order.apply(data).page(page).per(limit)
      includes.any? ? resources.includes(*includes) : resources
    end


    def data(current_user=nil)
      data = resource.send(attribute.to_s.pluralize)
      data = data.send(scoped) if options.key?(:scoped) and data.respond_to?(scoped)
      data
    end

    private

    def includes
      associated_dashboard.collection_includes
    end

    def candidate_resources
      if options.key?(:associated) 
        if resource.respond_to?(options[:associated])
          data = resource.send(options[:associated]).send(attribute.to_s.pluralize).send(scoped)
        else
          data = resource.send(attribute.to_s.pluralize)
        end
        # current_store_field.send(attribute.to_s.pluralize).send(scoped)
      elsif options.key?(:includes)
        includes = options.fetch(:includes)
        data = associated_class.includes(*includes).all
      else
        data = associated_class.all
      end
      data = data.send(scoped) if options.key?(:scoped) and data.respond_to?(scoped)
      order_options = options.key?(:sort_by) ? options[:sort_by].to_s : "id" 
      order_options = options.key?(:direction) ? order_options + options[:direction].to_s : order_options
      data = data.order(order_options) unless order_options.blank?
      data 
    end

    def display_candidate_resource(resource)
      associated_dashboard.display_resource(resource)
    end

    def associated_dashboard
      if options.key?(:dashboard) and options[:dashboard].try(:downcase).try(:to_s) == "control"
        if "Control::#{associated_class_name}Dashboard".is_a_defined_class?
          return "Control::#{associated_class_name}Dashboard".constantize.new
        end
      end
      super
    end

  end
end