class StoresController < ApplicationController
	layout "saasley"

	def new
		@store = Store.new
	end


	def create
		@store = Store.new(store_params)
		@store.state = "enable"
		# @store.url = @store.name.to_underscore
		# @store.name = @store.customers.try(:first).try(:name)
		respond_to do |format|
		  if store_params[:password].present? and @store.save
		  	customer_plan = @store.customer_plans.create(name: :example, amount:10.00, kind:'fixed', store:@store)
		  	customer = @store.customers.new(name:@store.name, customer_plan:customer_plan, role:'customer', role_control:'owner', store:@store)
		  	user = @store.users.create(email:store_params[:email], password:store_params[:password], userable:customer)
		  	if customer.save and user.valid?
			  	# @store.customers.first.update(user_id: @store.users.first.id, role: 'customer')

			  	sign_in(user)
			  	ContactMailer.email(user).deliver_now
			    format.html { redirect_to control_accounts_path }
		    	format.json { render :show, status: :created, location: @store }
			  else
					@store.errors.add(:base, :problem_on_create)
					format.html { render :new }
					format.json { render json: @store.errors, status: :unprocessable_entity }
			  end
		  else
		  	@store.errors.add(:password, :invalid_password) if store_params[:password].blank?
		    format.html { render :new }
		    format.json { render json: @store.errors, status: :unprocessable_entity }
		  end
		end
		
	end

	private
	  # Only allow a list of trusted parameters through.
	  def store_params
	    params.require(:store).permit(:name, :url, :plan_id, :password, :email) 
	  end

end