module SentientStore

	def self.included(base)

	  base.class_eval do

			def current_store
			  subdomain = request.subdomain.split('.').try(:first)
			  @current_store = Store.find_by(url: subdomain) unless subdomain.nil? 
			  @current_store ||= current_user.try(:store)
			end

		end
	end
end