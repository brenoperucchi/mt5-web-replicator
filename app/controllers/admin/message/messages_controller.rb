module Admin
	class Message::MessagesController < Admin::BaseController
    prepend AdministrateRansack::Searchable
		def resource_name
			::Message::Message
		end

		def resource_class 
			::Message::Message
		end

		def dashboard_class
			::Message::MessageDashboard
		end
	end
end