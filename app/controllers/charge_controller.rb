class ChargeController < ApplicationController
	layout 'stripe'
	skip_before_action :verify_authenticity_token, only: [:webhook]
	# before_action :authenticate_user!#, :find_model


	def index
		
	end


	def checkout
		# This is your test secret API key.
		Stripe.api_key = 'sk_test_51KXd9MFpK6wHohcRpF1nOLi6bp25UqS4h4lhfDsi9EWCc38ynCH0rfFabkYsz48YO6Xtg6vwUioki1qzmbtly8aZ00ObLPplFN'

		domain = 'http://localhost:80'


		@store = current_user.store

		if @store.plan  == "plan1"
			line_item = {price: 'price_1Kd5q2FpK6wHohcR3fov9Ll7', quantity:1}
		elsif @store.plan == "plan1"
			line_item = {price: 'price_1KbnzhFpK6wHohcRF1kSP0Ze'}
		end


	  session = Stripe::Checkout::Session.create({
	  	client_reference_id:'sub_1KbnotFpK6wHohcRfNuB9aiu',
	    line_items: [line_item],
	    mode: 'subscription',
	    success_url: domain + '/success.html',
	    cancel_url: domain + '/cancel.html',
	  })
	  redirect_to session.url
	end

	def webhook
		invoice = Invoice.find_by(stripe_invoice_id: params[:data][:object][:id])
		endpoint_secret = invoice.try(:invoiceable).try(:store).try(:stripe_webhook_secret)
		if endpoint_secret
			payload = request.body.read
			  event = nil
		  begin
		    event = Stripe::Event.construct_from(
		      JSON.parse(payload, symbolize_names: true)
		    )
		  rescue JSON::ParserError => e
		    # Invalid payload
		    puts "⚠️  Webhook error while parsing basic request. #{e.message})"
		    head 400
		  end
		  # Check if webhook signing is configured.
		  if endpoint_secret
		    # Retrieve the event by verifying the signature using the raw body and secret.
		    signature = request.env['HTTP_STRIPE_SIGNATURE'];
		    begin
		      event = Stripe::Webhook.construct_event(
		        payload, signature, endpoint_secret
		      )
		    rescue Stripe::SignatureVerificationError => e
		      puts "⚠️  Webhook signature verification failed. #{e.message})"
		      head 400
		    end
		  end

		  # Handle the event
		  case event.type
		  when 'invoice.payment_failed'
		    # invoice = event.data.object # contains a Stripe::Invoice
		    # Then define and call a method to handle the failed payment of an Invoice.
		    # handle_failed_invoice(invoice);
		  when 'invoice.finalized'
		  	invoice.update(state: 'open')
		  when 'payment_intent.succeeded'
		      payment_intent = event.data.object
		  		puts "🔔  Payment succeeded! (#{payment_intent.id}) - #{payment_intent.status}"
		  when 'invoice.payment_succeeded'
		  	invoice.update(state: 'paid')
		  else
		    puts "Unhandled event type: #{event.type}"
		  end
		  head 200
		

		else
			puts "⚠️  Not find stripe invoice id: #{params[:data][:object][:id]})"
			head 400
		end


	#   # You can use webhooks to receive information about asynchronous payment events.
	#   # For more about our webhook events check out https://stripe.com/docs/webhooks.
	#   webhook_secret = 'rk_test_51KXd9MFpK6wHohcRASCcxzUYVAg4PHnPHpJaxgTbbvNfS909qekZTYvviayeK7xX1FDmWwyFpQVCLDZRQkn7Ljjo00pHYE2iuZ'
	#   payload = request.body.read
	#   if !webhook_secret.empty?
	#     # Retrieve the event by verifying the signature using the raw body and secret if webhook signing is configured.
	#     sig_header = request.env['HTTP_STRIPE_SIGNATURE']
	#     event = nil

	#     begin
	#       event = Stripe::Webhook.construct_event(
	#         payload, sig_header, webhook_secret
	#       )
	#     rescue JSON::ParserError => e
	#       # Invalid payload
	#       status 400
	#       return
	#     rescue Stripe::SignatureVerificationError => e
	#       # Invalid signature
	#       puts '⚠️  Webhook signature verification failed.'
	#       status 400
	#       return
	#     end
	#   else
	#     data = JSON.parse(payload, symbolize_names: true)
	#     event = Stripe::Event.construct_from(data)
	#   end
	#   # Get the type of webhook event sent - used to check the status of PaymentIntents.
	#   event_type = event['type']
	#   data = event['data']
	#   data_object = data['object']

	#   puts '🔔  Payment succeeded!' if event_type == 'checkout.session.completed'

	#   content_type 'application/json'
	#   {
	#     status: 'success'
	#   }.to_json
	end

end