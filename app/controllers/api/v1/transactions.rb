require 'open-uri'
require 'json'
module API
	module V1
		class Transactions < Grape::API
			include API::V1::Defaults
			
		 resource :transactions do	
				desc 'Save message from telegram to rails api'
				get '' do
					transacations = Transaction.executed
				end
			end
    end
	end
end