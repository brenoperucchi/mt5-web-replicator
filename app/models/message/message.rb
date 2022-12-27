require "ancestry"

class Message::Message < ApplicationRecord
  self.table_name = "messages"
  has_ancestry
  
  has_many :orders, :class_name => "Order", :foreign_key => "message_id", dependent: :destroy
  has_many :transactions, through: :orders, source: :transactions,  dependent: :destroy
  # has_many :transactions, :class_name => "Transaction", :foreign_key => "message_id",  dependent: :destroy

  belongs_to :store, optional: true
  belongs_to :trace, optional: true 

end