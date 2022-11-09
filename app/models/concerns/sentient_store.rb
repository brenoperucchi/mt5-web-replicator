module SentientStore
	def self.included(base)

	  base.class_eval do

			def current_store_field(request = Store.first.url)
			  subdomain = request.split('.').try(:first)
			  @current_store ||= Store.find_by(url: subdomain) || Store.first   
			end

			def current_store
			  subdomain = request.subdomain.split('.').try(:first)
			  unless subdomain.nil? 
			  	session[:store_id] = Store.find_by(url: subdomain) || Store.first   
			  end
			end

		end
	end
end