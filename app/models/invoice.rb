require 'lib_enums'
class Invoice < ApplicationRecord

  include LibEnums
  include ActionView::Helpers::NumberHelper

  has_paper_trail 

  delegate :stripe_product_id, :stripe_customer_id, to: :store
  delegate :email, to: :invoiceable, allow_nil: true
  # delegate :trace, to: :plan_usage, allow_nil: true
  
  enum state: {pending: 0, open:1, paid: 2, denied:3, refunded:4}
  
  store :settings, accessors: [:email, :payment_link]

  serialize :response

  # belongs_to :ownerable, polymorphic: true
  belongs_to :store
  belongs_to :payment
  belongs_to :plan_usage, optional:true
  belongs_to :invoiceable, polymorphic: true, optional:true

  has_many :items, :class_name => "InvoiceItem", :foreign_key => "invoice_id", dependent: :destroy
  has_many :loggings,      as: :loggerable, dependent: :destroy

  accepts_nested_attributes_for :items, reject_if: :all_blank, allow_destroy: true


  def balance_update
    self.update(amount: items.to_a.sum(&:amount))  
  end


  def invoice_send
    payment_method = self.payment.payment_method.provider(self, self.payment)
    payment_method.checkout
    self.update(payment_link: payment_method.redirect_url)
    return payment_method
  end

  def customer
    self.invoiceable if respond_to?(:invoiceable) and self.invoiceable.is_a?(Customer)
  end


  def payment_method
    self.payment.payment_method.provider(self, self.payment)
  end

  def response
    read_attribute(:response) || {}
  end


end