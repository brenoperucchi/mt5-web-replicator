class	API::V2::APICopyPresenter 

	API_VERSION = "V2"

	def self.api_copy(params, request)


		# Logging.create(content:params, state: "COPY")
		account = Account.find_by(name: params[:account_id], kind: :copy)
		if account
		
		  unless params["imentore_copy"].valid_encoding?
		    params["imentore_copy"] = params["imentore_copy"].encode('UTF-8', 'binary', invalid: :replace, undef: :replace, replace: '')
		  end

		  attributes = {content: params["imentore_copy"], params: params.except("imentore_copy").to_json, request_url: request.url, content_at: Time.zone.now, store: account.try(:store), account:account}

		  # Message Open
		  message_open = Message::V2::Metatrader.new(attributes)
		  message_close = Message::V2::Metatrader.new(attributes)
		  
		  begin
		    message_open.save
		    message_close.save
		  rescue Exception => e
		    error_message = e.message
		    error_backtrace = e.backtrace[0..5]
		    logging = Logging.create(content: params, state: "COPY/ERROR", account: account, error_message: error_message, error_backtrace: error_backtrace)
		  end

		  if(message_open.valid?)
		    logging = message_open.loggings.create(content:params, state: "COPY/OPEN", changeset: account.name, account: account)
		    message_open.execute if message_open.create_orders(logging)
		  end

		  # Message Close
		  if(message_close.valid?)
		    logging = message_close.loggings.create(content:params, state: "COPY/CLOSE", changeset: account.name, account: account)
		    message_close.execute if message_close.close_orders(logging)
		  end

		  message_open.executed? and message_close.executed?
		end

		# if not message_open.traces.exists? and not message_open.orders.exists? and not message_open.slaves.exists?
		#   message_open.destroy
		# end
		# if not message_close.traces.exists? and not message_close.orders.exists? and not message_close.slaves.exists?
		#   message_close.destroy
		# end
		
		# if(message_open.executed? and message_close.executed?)
		# else
		#   status 401
		# end
  end
end