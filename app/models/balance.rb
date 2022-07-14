class Balance < ApplicationRecord
	belongs_to :account, optional: true
	belongs_to :order, optional: true
	belongs_to :master,  class_name: 'Transaction', 			foreign_key: 'master_id', optional: true
	belongs_to :slave,   class_name: 'TransactionSlave', 	foreign_key: 'slave_id', optional: true
end