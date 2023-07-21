class StoresController < ApplicationController
	prepend_before_action :check_captcha, only: [:create]
  respond_to :html, :xml, :json


	layout "saasley"

	def index
		@store = Store.new
		render :new
	end

	def new
		@store = Store.new
	end


	def create
		@store = Store.new(store_params)

		@store.state = "enable"
		# @store.url = @store.name.to_underscore
		# @store.name = @store.customers.try(:first).try(:name)
		password = Devise.friendly_token.first(6)
		url_name = "store#{Store.last.try(:id).to_i + 1}"
		@store.language = params[:locale].present? ? params[:locale] : 'pt-BR'
		@store.url = url_name
		@store.name = url_name
		@store.plan = Plan.first
		@store.payment = Store.first.payments.first

		respond_to do |format|
		  if @store.save
		  	PaymentMethod.all.each{|payment| payment.stores << @store}
		  	customer_plan = @store.customer_plans.create(name: :example, amount:10.00, kind:'fixed', store:@store, payment: @store.payments.first)
		  	customer = @store.customers.new(name:url_name, customer_plans:[customer_plan], role:'customer', role_control:'owner', store:@store)
		  	user = @store.users.create(email:store_params[:email], password:password, userable:customer)
		  	if customer.save and user.valid?
			  	# @store.customers.first.update(user_id: @store.users.first.id, role: 'customer')
			  	sign_in(user)
			  	ContactMailer.email(user, password).deliver_now
			    format.html { redirect_to control_accounts_path }
		    	format.json { render :show, status: :created, location: @store }
			  else
					@store.errors.add(:base, :problem_on_create)
					format.html { render :new }
					format.json { render json: @store.errors, status: :unprocessable_entity }
			  end
		  else
		  	# @store.errors.add(:password, :invalid_password) if store_params[:password].blank?
		    format.html { render :new }
		    format.json { render json: @store.errors, status: :unprocessable_entity }
		  end
		end
		
	end

	private

	def check_captcha
		unless Rails.env.test?
	  	alert_recaptcha unless verify_recaptcha
	  end
	end

	def alert_recaptcha
	  @store = Store.new store_params
	  respond_to do |format| 
	  	format.html { render :new }
	  end
	end

	  # Only allow a list of trusted parameters through.
	  def store_params
	    params.require(:store).permit(:name, :url, :plan_id, :password, :email) 
	  end

end