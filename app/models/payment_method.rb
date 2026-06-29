class PaymentMethod < ApplicationRecord
  # belongs_to :store

  has_many :invoices
  has_many :customer_plans

  has_many :payments, dependent: :destroy
  has_many :stores, through: :payments, source: :store
  
  # has_many :payment

  accepts_nested_attributes_for :payments

  def provider(payment)
    provider_class = "PaymentMethod::#{self.handle.classify}".safe_constantize
    @provider ||= provider_class.new(payment)
  end

end