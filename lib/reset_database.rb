require 'lib_enums'
require 'reset_database'
module ResetDatabase
	# def self.reset_database
	# 	Transaction.delete_all
	# 	TransactionSlave.delete_all
	# 	Order.delete_all
	# 	Deal.delete_all
	# 	Message.delete_all
	# 	Balance.delete_all
	# 	Logging.delete_all
	# 	Message.delete_all
	# end

	def self.delete_logging
		# Logging.where(state: "OPEN", loggerable_type:'TransactionSlave').delete_all
		Logging.where(state: "START").delete_all
		Message::Message.joins('LEFT JOIN messages_traces ON messages_traces.message_id = messages.id').joins('LEFT JOIN messages_orders ON messages_orders.message_id = messages.id').where('messages_traces.trace_id IS NULL').where('messages_orders.order_id IS NULL').delete_all
		date = DateTime.now - 6.months
		conditions = date.beginning_of_year..date.end_of_day
		Logging.where(state: "MODIFY", created_at: conditions).delete_all
		Logging.where(state: "COPY/MODIFY", created_at: conditions).delete_all
		Logging.where(state: "COPY/CLOSE", created_at: conditions).delete_all
		Logging.where(state: "ORDERS_CLOSED", created_at: conditions).delete_all
		Logging.where(state: "ORDERS_OPEN", created_at: conditions).delete_all
		Message::Message.where(state: "executed", created_at: conditions).delete_all

		# date = DateTime.parse("2022-01-01")
		# Logging.where(created_at:date.beginning_of_year..date.end_of_year).delete_all
		# Message::Message.where(created_at:date.beginning_of_year..date.end_of_year).delete_all
	end


	def self.transaction_slave_cleaning
		map = TransactionSlave.select(:ticket_master,:account_id).group(:ticket_master,:account_id).having("count(*) > 1").size.map{|x| x[0]}
		map.each do |x, z| 
			slave = TransactionSlave.where(ticket_master: x, account_id: z, state: "deleted").take
			slave.destroy unless slave.nil?
			slave = TransactionSlave.where(ticket_master: x, account_id: z, state: "error").take
			slave.destroy unless slave.nil?
			slave = TransactionSlave.where(ticket_master: x, account_id: z, state: "closed", ticket_slave:-1).take
			slave.destroy unless slave.nil?
		end

	end


	def self.reset_trace(trace_id, account_id, store_id)
		trace = Trace.find(trace_id)
		account = Account.find(account_id)
		store = Store.find(store_id)

		new_trace = Trace.create(name: "Migrate Trace #{trace.name} ##{trace.id} - Account #{account.name} ID ##{account_id}", name_id: DateTime.now.to_i, kind:"copy", customer_plans: [Store.first.customer_plans.first], active: false, contract_volume_max:1, store:store)
		Order.where(account_id: account_id, trace_id: trace_id).each do |o|
			o.update(trace: new_trace)
			o.transactions.update_all(trace_id: new_trace.id)
			o.slaves.update_all(trace_id: new_trace.id)
		end


		# Trace.find(trace_id).masters.where(account_id: account_id).each do |t|
		# 	t.order.slaves.update_all(trace_id: new_trace.id)
		# 	t.order.update(trace:new_trace)
		# 	t.update(trace: new_trace)
		# end
	end

	def self.migrate_db_production
		Store.all.each do|s| 
			s.update(url: s.url + "2") unless s.url.include?("2")
		end
		payments = Payment.all.order(id: :asc).limit(2)
		payments.update_all(api_token: 'TEST-8003379344962428-070514-132303626f6b89ba73ab9f77b2a95c9d-77964627', webhook_token:'TEST-ea4aec5d-82ed-42c8-8c8a-abdd14b3690a') if payments.present?
	end

	def self.transaction_delete_loggings_closed
	  Transaction.all.each do |transaction|
	    closed_logging = transaction.loggings.where(state: "CLOSED").order(created_at: :desc)
	    if closed_logging.count > 1
	      closed_logging[1..-1].each do |logging|
	        logging.delete
	      end
	    end
	  end
	end

end