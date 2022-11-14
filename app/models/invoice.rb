require 'lib_enums'
class Invoice < ApplicationRecord
  ENUMS = %w(state)

  include LibEnums

  delegate :stripe_product_id, :stripe_customer_id, to: :invoiceable
  delegate :email, to: :invoiceable
  
  enum state: {pending: 0, open:1, paid: 2, denied:3}
  
  store :settings, accessors: [:email, :payment_link]

  # belongs_to :ownerable, polymorphic: true
  belongs_to :invoiceable, polymorphic: true
  has_many :items, :class_name => "InvoiceItem", :foreign_key => "invoice_id", dependent: :destroy

  accepts_nested_attributes_for :items, reject_if: :all_blank, allow_destroy: true


  def balance_update
    self.update(amount: items.sum(:amount))  
  end

  def invoice_send
    return false if self.state != 'pending'
    changes = false;

    # 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

    # Stripe.api_key = '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'
    # Stripe.api_key = 'sk_test_51KXd9MFpK6wHohcRpF1nOLi6bp25UqS4h4lhfDsi9EWCc38ynCH0rfFabkYsz48YO6Xtg6vwUioki1qzmbtly8aZ00ObLPplFN'

    Stripe.api_key = self.try(:invoiceable).try(:store).try(:stripe_api_secret)

    if invoiceable.stripe_product_id.blank?
      product = Stripe::Product.create(name: "#{self.name} - Monthly Payment - #{invoiceable.email}")
      invoiceable.update(stripe_product_id: product[:id])
      changes = true
    end

    price = Stripe::Price.create(
      product: invoiceable.stripe_product_id,
      unit_amount: self.amount.to_s.gsub(".","").gsub(",",""),
      currency: 'brl',
    )


    if invoiceable.stripe_customer_id.blank?
      customer = Stripe::Customer.create(
        name: invoiceable.name,
        email: invoiceable.email,
        description: 'My first customer',
      )
      invoiceable.update(stripe_customer_id: customer[:id])
      changes = true
    end

    invoice_item = Stripe::InvoiceItem.create(
      customer: invoiceable.stripe_customer_id,
      price: price[:id],
    )

    invoice = Stripe::Invoice.create(
      customer: invoiceable.stripe_customer_id,
      collection_method: 'send_invoice',
      days_until_due: 10,
      payment_settings: {
            payment_method_types: ['card'],
          },
    )

    if invoice[:id]
      self.update(stripe_invoice_id: invoice[:id]) 
      Stripe::Invoice.finalize_invoice(invoice[:id])
      invoice = Stripe::Invoice.send_invoice(invoice[:id])
      self.update(payment_link: invoice[:hosted_invoice_url])
    else
      self.update(state: :error)
      return false
    end
    
    return true
  end

end
