class StoresController < ApplicationController
	prepend_before_action :check_captcha, only: [:create]
  respond_to :html, :xml, :json

	layout "saasley"

	def index
		@store = Store.new
		render :new
	end

	def new
		@store = Store.new(email: params.dig(:store, :email))
	end


	def create
		@store = Store.new(store_params)

		@store.state = "enable"
		password   = 123123
		store_name = "Sistema-#{Store.maximum(:id) + 1}"
		url_name 	 = store_name.to_underscore
		email 	   = store_params[:email]
		@store.language = set_locale
		@store.url = url_name
		@store.name = store_name
		@store.plan = Plan.first
		@store.payment = Payment.first

		respond_to do |format|
		  if @store.save
		  	
		  	if @store.create_association_after_create(email, password)
			  	# @store.customers.first.update(user_id: @store.users.first.id, role: 'customer')
			  	user = @store.users.first
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
		  Rails.logger.info "Params: #{store_params.inspect}"
		  Rails.logger.info "Stores: #{@store.inspect}"
		  Rails.logger.info "Errors: #{@store.errors.inspect}"
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