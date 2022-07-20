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
end