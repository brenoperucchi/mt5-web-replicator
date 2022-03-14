class Balance < ApplicationRecord
	belongs_to :account
	belongs_to :deal,  class_name: 'Transaction', foreign_key: 'deal_id'
	belongs_to :slave, class_name: 'TransactionSlave', foreign_key: 'slave_id', optional: true

end