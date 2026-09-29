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

  # Returns the provider adapter (PaymentMethod::<Handle>) bound to the given
  # payment, or nil when no adapter exists for this handle (e.g. legacy
  # 'mercado_pago' rows). A new instance is built on every call because each
  # payment carries its own credentials.
  def provider(payment)
    provider_class = "PaymentMethod::#{handle.to_s.classify}".safe_constantize
    if provider_class.nil? || !provider_class.method_defined?(:checkout)
      Rails.logger.warn("PaymentMethod##{id}: no provider available for handle '#{handle}'")
      return nil
    end
    provider_class.new(payment)
  end

end
