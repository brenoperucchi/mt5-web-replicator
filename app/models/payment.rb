class Payment < ApplicationRecord
  belongs_to :payment_method
  belongs_to :store, optional:true

  has_many :customer_plans
  has_many :invoices

  has_many :tokens, as: :resourceable, dependent: :destroy


  delegate :name, to: :payment_method, allow_nil: true

  def webook_url
    "https://#{Store.first.domain_url}:8443/#{self.payment_method.handle.classify.downcase}/webhook/#{store.id}/#{self.id}"
  end
end
