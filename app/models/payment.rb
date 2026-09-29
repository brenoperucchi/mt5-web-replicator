class Payment < ApplicationRecord
  belongs_to :payment_method
  belongs_to :store, optional:true

  has_many :customer_plans
  has_many :invoices

  has_many :tokens, as: :resourceable, dependent: :destroy


  delegate :name, to: :payment_method, allow_nil: true

  # def method(invoice)
  #   "PaymentMethod::#{payment_method.handle.classify}".safe_constantize.new(invoice, self)
    
  # end

  # Endpoint to register in the provider dashboard (e.g. Stripe webhooks).
  def webook_url
    "https://#{Store.domain_url}/payments/webhook/#{self.id}"
  end
end
