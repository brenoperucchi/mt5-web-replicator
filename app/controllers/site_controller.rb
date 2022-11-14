class SiteController < ApplicationController
	layout "saasley"
	before_action :set_locale

	def index


	end


	def set_locale
		locale = params[:locale]
		case locale
		when "en"
			I18n.locale = :en
		else
			I18n.locale = 'pt-BR'
		end
	end

end
