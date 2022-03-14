class ChargeController < ApplicationController
	layout 'stripe'

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
	  # You can use webhooks to receive information about asynchronous payment events.
	  # For more about our webhook events check out https://stripe.com/docs/webhooks.
	  webhook_secret = 'rk_test_51KXd9MFpK6wHohcRASCcxzUYVAg4PHnPHpJaxgTbbvNfS909qekZTYvviayeK7xX1FDmWwyFpQVCLDZRQkn7Ljjo00pHYE2iuZ'
	  payload = request.body.read
	  if !webhook_secret.empty?
	    # Retrieve the event by verifying the signature using the raw body and secret if webhook signing is configured.
	    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
	    event = nil

	    begin
	      event = Stripe::Webhook.construct_event(
	        payload, sig_header, webhook_secret
	      )
	    rescue JSON::ParserError => e
	      # Invalid payload
	      status 400
	      return
	    rescue Stripe::SignatureVerificationError => e
	      # Invalid signature
	      puts '⚠️  Webhook signature verification failed.'
	      status 400
	      return
	    end
	  else
	    data = JSON.parse(payload, symbolize_names: true)
	    event = Stripe::Event.construct_from(data)
	  end
	  # Get the type of webhook event sent - used to check the status of PaymentIntents.
	  event_type = event['type']
	  data = event['data']
	  data_object = data['object']

	  puts '🔔  Payment succeeded!' if event_type == 'checkout.session.completed'

	  content_type 'application/json'
	  {
	    status: 'success'
	  }.to_json
	end

end