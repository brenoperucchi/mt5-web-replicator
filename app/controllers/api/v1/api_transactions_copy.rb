# require 'open-uri'
require 'json'
module API
	module V1
		class APITransactionsCopy < Grape::API
			include API::V1::Defaults

			resource :transactions do	
				# desc "Example Request Transaction"
				# get "/copy/trasmit/:expert_name/:expert_version/:account_id" do
				# 	puts params
				# 	account = Account.find_by(name: params[:account_id])
				# 	if account
				# 		map = account.slaves.executed.collect do |t| 
				# 			attributes = t.meta_attributes
				# 			"#{attributes[:trace_id]}|#{attributes[:instrument]}|#{attributes[:transaction_id]}|#{attributes[:ordertype]}|#{attributes[:openprice]}|#{attributes[:volume]}|#{attributes[:stoploss]}|#{attributes[:takeprofit]}|#{attributes[:magic_number]}"
				# 		end.join('/')
				# 	end
				# 	content_type 'text/plain'
				# 	body map
				# end

				desc "Receive Transaction"
				post "/copy/trasmit/:expert_name/:expert_version/:account_id" do
					map = String.new
					params_body = params[:body]
					content = YAML.load(params_body)
					account = Account.find_by(name: params[:account_id], kind: :copy)

					trace = account.try(:trace_copy)
					return if account.nil?
					magic_number = account.magics_accept.try(:split).try(:include?, content['magic_number'])
					
					# trace = Trace.all.detect{|x| x.accounts_accept.try(:split).try(:include?, params[:account_id])}
					# magic_number = Trace.all.detect{|x| x.magics_accept.try(:split).try(:include?, content['magic_number'])}

					if magic_number and trace and not content.blank? and content.is_a?(Hash)
					  print(params_body)
					  case content['action']
					  when "OPEN"
					    comment = content['comment']
					    epoch_time = content['open_at'].split(".").first.to_i
					    d = Time.at(epoch_time).utc.to_datetime
					    # content_at = Time.zone.local(d.year,d.month,d.day,d.hour,d.minute,d.second)

					   	content_at = Time.new(d.year, d.month, d.day,d.hour,d.minute,d.second, "-03:00").to_datetime
					    # content_at = Time.at(epoch_time.to_i).utc.to_datetime
					    # Time.zone = "GMT"
					    # Time.zone.at(epoch_time.to_i)
					    # Time.zone = "Brasilia"
					    # Time.zone.at(epoch_time.to_i)
					    message = trace.messages.create(content: params_body, content_id: comment, content_at: content_at, store: trace.store)
					    message.prepare
					    if message.transactions
					    	message.transactions.each do |t|
					    		t.loggings.create(content:params_body)
					    		t.update(ticket: content['order_ticket'], price_open:content['open_price'], open_at: Time.at(content['open_at'].split(".").first.to_i))
					    		map = "#{t.order.trace.id}|#{t.id}|OK"
					    	end
					    end
					  when "MODIFY"
					    ticket_id = content['order_ticket']
				      transactions = Transaction.where(ticket: ticket_id)
					    transactions.each do |transaction|
					      transaction.loggings.create(content:params_body)
					      transaction.set_sl_and_tp_order(take_profit=content['take_profit'], stop_loss=content['stop_loss'])
					      attributes = transaction.copy_attributes
					      map = "#{attributes[:trace_id]}|#{attributes[:transaction_id]}|OK"
					    end
					  when "CLOSE"
				    	ticket_id = content['order_ticket']
				      	transactions = Transaction.where(ticket: ticket_id)
					    transactions.each do |transaction|
					      transaction.loggings.create(content:params_body)
					      transaction.profit = content['profit']
					      transaction.close_order
					      attributes = transaction.copy_attributes
					      map = "#{attributes[:trace_id]}|#{attributes[:transaction_id]}|OK"
					    end
						end
					end
					content_type 'text/plain'
					body map
				end
				##############################################
			end
		end
	end
end