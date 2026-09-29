class PaymentMethod < ApplicationRecord
  # Raised by providers when a webhook payload fails signature verification.
  class SignatureError < StandardError; end

  # belongs_to :store

  has_many :invoices
  has_many :customer_plans

  has_many :payments, dependent: :destroy
  has_many :stores, through: :payments, source: :store
  
  # has_many :payment

  accepts_nested_attributes_for :payments

  # Adapter class (PaymentMethod::<Handle>) for a handle, or nil when none
  # exists (e.g. legacy 'mercado_pago' rows).
  def self.provider_class_for(handle)
    klass = "PaymentMethod::#{handle.to_s.classify}".safe_constantize
    klass if klass && klass.method_defined?(:checkout)
  end

  # Payment methods whose provider adapter exists.
  scope :available, -> {
    where(handle: unscoped.distinct.pluck(:handle).select { |handle| provider_class_for(handle) })
  }

  def available?
    self.class.provider_class_for(handle).present?
  end

  # Returns the provider adapter bound to the given payment, or nil when no
  # adapter exists for this handle. A new instance is built on every call
  # because each payment carries its own credentials.
  def provider(payment)
    provider_class = self.class.provider_class_for(handle)
    if provider_class.nil?
      Rails.logger.warn("PaymentMethod##{id}: no provider available for handle '#{handle}'")
      return nil
    end
    provider_class.new(payment)
  end

end
