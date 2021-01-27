class Store < ApplicationRecord
  acts_as_taggable_on :tags

  has_many :traces, :class_name => "Trace", :foreign_key => "store_id"
  has_many :orders, :through => :traces, :source => :orders
  
  has_many :messages, :class_name => "Message", :foreign_key => "store_id"
  has_many :transactions, :through => :messages, :source => :transactions
  store :settings, accessors: [:master, :slaves]

  scope :active, ->{ where.not(active_at:nil)}
end