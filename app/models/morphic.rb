class Morphic < ApplicationRecord
	  belongs_to :account, optional: true
	  belongs_to :tmaster, :class_name => "Transaction", :foreign_key => "transaction_id"
end