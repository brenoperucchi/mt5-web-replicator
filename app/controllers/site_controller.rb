class SiteController < ApplicationController
	layout "saasley"

	def index
		@dolar = 5
	end

	def support
	end

	def demo_request
		redirect_to new_store_path(locale:params[:locale])
	end


end
