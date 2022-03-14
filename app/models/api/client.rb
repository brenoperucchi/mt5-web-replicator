module Api
  class Client
    include ActiveModel::Model
    attr_accessor :id, :name, :email, :active, :plan, :created_at, :updated_at, :destroy


    def errors=(attributes)
      # @errors = ActiveModel::Errors.new(self)
      return unless attributes.present?
      attributes.each do |error|
        self.errors.add(error['attribute'].to_sym, error['type'].to_sym, message: error['options']['message'])
      end
      self.define_singleton_method(:valid?) { false } 

    end
  end
end