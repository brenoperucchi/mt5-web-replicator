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
		Logging.where(state: "OPEN", loggerable_type:'TransactionSlave').delete_all
		Logging.where(state: "START").delete_all
		Logging.where(state: "MODIFY").delete_all
		Message::Message.all.each{|x| x.orders.blank? ? x.destroy : true}
		date = DateTime.now - 1.year
		Logging.where(created_at:date.beginning_of_year..date.end_of_year).delete_all
		Message::Message.where(created_at:date.beginning_of_year..date.end_of_year).delete_all
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

end

