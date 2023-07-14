class PaymentMethod::Stripe

	# def self.options
	#   @options ||= [:api_token, :webhook_token]
	# end

	def initialize(*args)
		@invoice, @payment = args
		# @customer, @item, @logging @invoice.invoiceable = customer, item, logging, invoiceable
	end

	def checkout
	  return false if @invoice.state != 'pending'
	  changes = false;

	  Stripe.api_key = @payment.api_token
	  # Stripe.api_key = @invoice.invoiceable.try(:store).try(:stripe_api_secret)


	  stripe_product = @invoice.invoiceable.tokens.find_or_create_by(resourceable:@payment)	

	  if stripe_product.name.nil?
	    product = Stripe::Product.create(name: "#{@invoice.name} - Monthly Payment - #{@invoice.invoiceable.email}")
	    stripe_product.update(name: product[:id])
	    # @invoice.invoiceable.update(stripe_product_id: product[:id])
	    changes = true
	  end

	  price = Stripe::Price.create(
	    product: stripe_product.name,
	    # product: @invoice.invoiceable.stripe_product_id,
	    unit_amount: number_with_precision(@invoice.amount, precision: 2).to_s.gsub(/[.,]/,""),
	    currency: 'brl',
	  )


	  if @invoice.invoiceable.stripe_customer_id.blank?
	    customer = Stripe::Customer.create(
	      name: @invoice.invoiceable.name,
	      email: @invoice.invoiceable.email,
	      description: 'My first customer',
	    )
	    @invoice.invoiceable.update(stripe_customer_id: customer[:id])
	    changes = true
	  end

	  invoice_item = Stripe::InvoiceItem.create(
	    customer: @invoice.invoiceable.stripe_customer_id,
	    price: price[:id],
	  )

	  invoice_api = Stripe::Invoice.create(
	    customer: @invoice.invoiceable.stripe_customer_id,
	    collection_method: 'send_invoice',
	    days_until_due: 10,
	    payment_settings: {
	        },
	  )

	  if invoice_api[:id]
	    @invoice.update(stripe_invoice_id: invoice_api[:id]) 
	    Stripe::Invoice.finalize_invoice(invoice_api[:id])
	    payment_response = Stripe::Invoice.send_invoice(invoice_api[:id])
	    # @invoice.update(payment_link: invoice_api[:hosted_invoice_url])
	    @invoice.update(response: payment_response.to_json)
	  else
	    @invoice.update(state: :error)
	    return false
	  end

	  def redirect_url
 			YAML.load(@invoice.response)["hosted_invoice_url"]
	  end
	  
	  return true
	end

end