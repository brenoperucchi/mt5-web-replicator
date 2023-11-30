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

  def webook_url
    if Rails.env.production?
      "https://#{Store.domain_url}/#{self.payment_method.handle.classify.downcase}/webhook/#{store.id}/#{self.id}"
    else
      "https://#{Store.domain_url}/#{self.payment_method.handle.classify.downcase}/webhook/#{store.id}/#{self.id}"
    end
  end
end
