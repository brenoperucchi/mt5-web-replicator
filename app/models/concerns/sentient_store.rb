module SentientStore

	def self.included(base)

	  base.class_eval do
			# def current_store_field(request, current_user=nil)
			# 	if current_user
			# 		# if current_user.try(:store).url != subdomain
			# 		# 	# redirect_to new_user_session_path, notice:"User not authorized for this Store"
			# 		# end
			# 		current_user.try(:store)
			# 	else
			#   	subdomain = request.split('.').try(:first)
			#   	@current_store ||= Store.find_by(url: subdomain) || Store.first   
			#   end
			# end

			def current_store
			  subdomain = request.subdomain.split('.').try(:first)
			  @current_store = Store.find_by(url: subdomain) unless subdomain.nil? 
			  @current_store ||= current_user.try(:store)
			  # session[:store_id] ||= Store.first
			end

		end
	end
end