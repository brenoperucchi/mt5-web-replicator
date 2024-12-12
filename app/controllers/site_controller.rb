class SiteController < ApplicationController
	layout "prompt"

	def index
		@dolar = 6
		@store = Store.new 
	end

	def support
	end

	def demo_request
		redirect_to new_store_path(locale:params[:locale])
	end


	def robos
		render :robos, layout:'mintone'
	end

	def partner
	end

end