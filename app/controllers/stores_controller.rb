class StoresController < ApplicationController
	layout 'tailwind'

	def new
		@store = Store.new
	end


	def create
		@store = Store.new(store_params)
		@store.state = "enable"
		@store.name = @store.customers.try(:first).try(:name)
		respond_to do |format|
		  if @store.save
		  	@store.customers.first.update(user_ids: @store.users.first.id, role: 'customer')
		  	sign_in(@store.users.first)
		    format.html do 
		    	if @store.plan == "plan2"
		    		redirect_to control_accounts_path, notice: 'Client was successfully created.' 
		    	elsif @store.plan == "plan1"
		    		redirect_to checkout_charge_path
		    	end
		    end
		    format.json { render :show, status: :created, location: @client }
		  else
		    format.html { render :new }
		    format.json { render json: @client.errors, status: :unprocessable_entity }
		  end
		end
		
	end

	private
	  # Only allow a list of trusted parameters through.
	  def store_params
	    params.require(:store).permit(:name, :plan, customers_attributes:[:name], users_attributes:[:email, :password, :password_confirmation])
	  end

end