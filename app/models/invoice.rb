require 'lib_enums'
class Invoice < ApplicationRecord
  ENUMS = %w(state)

  include LibEnums
  
  enum state: {pending: 0, paid: 1, denied:2}
  
  store :settings, accessors: [:email, :stripe_product_id, :stripe_customer_id]

  # belongs_to :ownerable, polymorphic: true
  belongs_to :invoiceable, polymorphic: true
  has_many :items, :class_name => "InvoiceItem", :foreign_key => "invoice_id", dependent: :destroy


  def balance_update
    self.update(amount: items.sum(:amount))  
  end

  def invoice_send
    changes = false;

    Stripe.api_key = 'sk_test_51KXd9MFpK6wHohcRpF1nOLi6bp25UqS4h4lhfDsi9EWCc38ynCH0rfFabkYsz48YO6Xtg6vwUioki1qzmbtly8aZ00ObLPplFN'

    
    if stripe_product_id.blank?
      product = Stripe::Product.create(name: "#{self.name} - Monthly Payment - #{invoiceable.email}")
      self.stripe_product_id = product[:id]
      changes = true
    end

    price = Stripe::Price.create(
      product: stripe_product_id,
      unit_amount: self.amount.to_s.gsub(".","").gsub(",",""),
      currency: 'brl',
    )


    if stripe_customer_id.blank?
      customer = Stripe::Customer.create(
        name: invoiceable.name,
        email: invoiceable.email,
        description: 'My first customer',
      )
      self.stripe_customer_id = customer[:id]
      changes = true
    end

    invoice_item = Stripe::InvoiceItem.create(
      customer: self.stripe_customer_id,
      price: price[:id],
    )

    invoice = Stripe::Invoice.create(
      customer: self.stripe_customer_id,
      collection_method: 'send_invoice',
      days_until_due: 10,
    )

    Stripe::Invoice.send_invoice(invoice[:id])

  end

end
