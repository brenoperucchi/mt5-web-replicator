require "administrate/field/associative.rb"
require "administrate/page/collection"
require "administrate/order"
require "sentient_store.rb"

module Fields
  class HasManyScopeField < Administrate::Field::HasMany
    include SentientStore

    def to_s
      data
    end

    # def associated
    #   options[:associated] if options.key?(:associated)
    # end

    def scoped
      options[:scoped] if options.key?(:scoped)
    end


    def associated_resource_options
      candidate_resources.map do |resource|
        [display_candidate_resource(resource), resource.send(primary_key)]
      end
    end


    def data
      @data ||= candidate_resources
      # if options.key?(:associated)
      #   @data ||= current_store_field.send(associated_class.name.pluralize.downcase.to_sym).send(options[:scoped].to_sym)
      # elsif options.key?(:scoped)
      #   @data ||= resource.send(associated_class.name.pluralize.downcase.to_sym).send(options[:scoped].to_sym)
      # else
      #   @data ||= associated_class.none
      # end

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

    private

    def includes
      associated_dashboard.collection_includes
    end

    def candidate_resources
      if options.key?(:associated)
        current_store_field.send(associated_class.name.pluralize.downcase.to_sym).send(scoped)
      elsif options.key?(:scoped)
        resource.send(associated_class.name.pluralize.downcase.to_sym).send(options[:scoped].to_sym)
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