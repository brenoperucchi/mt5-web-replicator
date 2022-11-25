module SentientStore
	def self.included(base)

	  base.class_eval do

			def current_store_field(request = Store.first.url)
				if user_signed_in?
					current_user.try(:store)
				else
			  	subdomain = request.split('.').try(:first)
			  	@current_store ||= Store.find_by(url: subdomain) || Store.first   
			  end
			end

			def current_store
				if user_signed_in?
					current_user.try(:store)
				else
				  subdomain = request.subdomain.split('.').try(:first)
				  unless subdomain.nil? 
				  	session[:store_id] = Store.find_by(url: subdomain) || Store.first   
				  end
				end
			end

		end
	end
end