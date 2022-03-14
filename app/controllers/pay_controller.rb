class PayController < ApplicationController
	before_action :authenticate_user!, :find_model

	def checkout
		@customer.set_payment_processor :stripe
		@customer.payment_processor.customer

		@checkout_session = @customer.payment_processor.checkout(
		  mode: 'subscription',
		  line_items: "price_1KZ50jFpK6wHohcRhklSV7BD"
		)
		
	end

	def subscription
		@customer.set_payment_processor :stripe
		@customer.payment_processor.customer

		@checkout_session = @customer.payment_processor.checkout(
		  mode: 'subscription',
		  line_items: "price_1Kb7iiFpK6wHohcRc5a4nha3"
		)
		
	end

	def billing
		@portal_session = @customer.payment_processor.billing_portal
	end

	private
	def find_model
		@customer = current_user.customer
		@model = Pay.find(params[:id]) if params[:id]
	end
end