require "ancestry"
class Message < ApplicationRecord
	has_ancestry
	
	has_one :order, :class_name => "Order", :foreign_key => "message_id", dependent: :destroy
	has_many :transactions, :class_name => "Transaction", :foreign_key => "message_id",  dependent: :destroy

	belongs_to :store, optional: true
	belongs_to :trace, optional: true	
end