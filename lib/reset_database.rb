require 'lib_enums'
require 'reset_database'
module ResetDatabase
	def self.reset_database
		Transaction.delete_all
		TransactionSlave.delete_all
		Order.delete_all
		Deal.delete_all
		Message.delete_all
		Balance.delete_all
		Logging.delete_all
		Message.delete_all
	end

	def self.delete_logging
		Logging.where(state: "OPEN", loggerable_type:'TransactionSlave').delete_all
		Logging.where(state: "START").delete_all
		Logging.where(state: "MODIFY").delete_all
		Message::Message.all.each{|x| x.orders.blank? ? x.destroy : true}
		date = DateTime.now - 1.year
		Logging.where(created_at:date.beginning_of_year..date.end_of_year).delete_all
		Message::Message.where(created_at:date.beginning_of_year..date.end_of_year).delete_all
	end

end

