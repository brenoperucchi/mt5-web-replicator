module SentientStore
	def self.included(base)

	  base.class_eval do

			def current_store_field(request = Store.first.url)
			  subdomain = request.split('.').try(:first)
			  Rails.logger.info("SUB DOMAIN #{request}")
			  Rails.logger.info("SUB DOMAIN SPLIT #{subdomain}")
			  @current_store ||= Store.find_by(url: subdomain) || Store.first   
			  # session[:store_id] = Store.find_by(url: subdomain) || Store.first   
			  # Store.current = session[:store_id]
			end

			def current_store
			  subdomain = request.subdomain.split('.').try(:first)
			  Rails.logger.info("SUB DOMAIN #{request.subdomain}")
			  Rails.logger.info("SUB DOMAIN SPLIT #{subdomain}")
			  session[:store_id] = Store.find_by(url: subdomain) || Store.first   
			end

		end
	end
end