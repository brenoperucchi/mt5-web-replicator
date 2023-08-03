require 'mercadopago'
class PaymentMethod::MercadoPago

	# def self.options
	#   @options ||= [:api_token, :webhook_token]
	# end

	def initialize(*args)
		@invoice, @payment = args
		# @customer, @item, @logging @invoice.invoiceable = customer, item, logging, invoiceable
	end

	def redirect_url
		@payment_response["init_point"] || false
	end

	def payment_id
		@payment_response["id"]
	end

	def public_key
		@payment.webhook_token
	end

	def checkout
		sdk = Mercadopago::SDK.new(@payment.api_token)

		if @invoice.invoiceable_type == "Customer"
			title = "Inscrição #{@invoice.plan_usage.usageable.name}"
		else
			title = "Plano Imentore - #{@invoice.items.first.name}"
		end

		preference_data = {

			back_urls: {failure:"https://signallocal.imentore.com.br:8443/mercadopago/webhook/#{@payment.store.id}"},
			external_reference: @invoice.id,
		  items: [
		    {
		    	id: @invoice.id,
		      title: title,
		      unit_price: number_with_precision(@invoice.amount, precision: 2, locale: :en).to_f,
		      quantity: 1
		    }
		  ]
		}
		preference_response = sdk.preference.create(preference_data)
		@invoice.update(response: preference_response)

		@payment_response = preference_response[:response]

		# This value replaces the String "<%= @preference_id %>" in your HTML

		# customer_request = {
		#   email: @invoice.invoiceable.email
		# }

		# customer_response = sdk.customer.create(customer_request)
		# customer = customer_response[:response]

		# token = @invoice.invoiceable.tokens.find_or_create_by(resourceable:@payment)


		# cards_response = sdk.card.list(token.name)
		# cards = cards_response[:response]
		# binding.pry


		# payment_methods_response = sdk.payment_methods.get()
		# payment_methods = payment_methods_response[:response]

		# payment_data = {
		#   transaction_amount: number_with_precision(@invoice.amount, precision: 2).to_s.gsub(/[.,]/,""),
		#   token: 'CARD_TOKEN',
		#   description: 'Payment description',
		#   payment_method_id: 'visa',
		#   installments: 1,
		#   payer: {
		#     email: 'test_user_123456@testuser.com'
		#   }
		# }
		# result = sdk.payment.create(payment_data)
		# payment = result[:response]

	  # return false if @invoice.state != 'pending'
	  # changes = false;

	  # Stripe.api_key = @payment.api_token
	  # # Stripe.api_key = @invoice.invoiceable.try(:store).try(:stripe_api_secret)

	  # if @invoice.invoiceable.stripe_product_id.blank?
	  #   product = Stripe::Product.create(name: "#{@invoice.name} - Monthly Payment - #{@invoice.invoiceable.email}")
	  #   @invoice.invoiceable.update(stripe_product_id: product[:id])
	  #   changes = true
	  # end

	  # price = Stripe::Price.create(
	  #   product: @invoice.invoiceable.stripe_product_id,
	  #   unit_amount: number_with_precision(@invoice.amount, precision: 2).to_s.gsub(/[.,]/,""),
	  #   currency: 'brl',
	  # )


	  # if @invoice.invoiceable.stripe_customer_id.blank?
	  #   customer = Stripe::Customer.create(
	  #     name: @invoice.invoiceable.name,
	  #     email: @invoice.invoiceable.email,
	  #     description: 'My first customer',
	  #   )
	  #   @invoice.invoiceable.update(stripe_customer_id: customer[:id])
	  #   changes = true
	  # end

	  # invoice_item = Stripe::InvoiceItem.create(
	  #   customer: @invoice.invoiceable.stripe_customer_id,
	  #   price: price[:id],
	  # )

	  # invoice_api = Stripe::Invoice.create(
	  #   customer: @invoice.invoiceable.stripe_customer_id,
	  #   collection_method: 'send_invoice',
	  #   days_until_due: 10,
	  #   payment_settings: {
	  #       },
	  # )

	  # if invoice_api[:id]
	  #   @invoice.update(stripe_invoice_id: invoice_api[:id]) 
	  #   Stripe::Invoice.finalize_invoice(invoice_api[:id])
	  #   invoice_api = Stripe::Invoice.send_invoice(invoice_api[:id])
	  #   @invoice.update(payment_link: invoice_api[:hosted_invoice_url])
	  # else
	  #   @invoice.update(state: :error)
	  #   return false
	  # end
	  
	  # return true
	end

end