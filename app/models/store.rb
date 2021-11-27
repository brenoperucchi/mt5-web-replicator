class Store < ApplicationRecord

  store :settings, accessors: [:master, :telegram_api_id, :telegram_api_number, :telegram_api_hash, :volume_default, :server_url, :server_real]
  enum state: {pending:0, active:1, deleted:2}
  
  acts_as_taggable_on :tags

  has_many :accounts, :class_name => "Account", :foreign_key => "store_id"
  has_many :traces, :class_name => "Trace", :foreign_key => "store_id"
  has_many :orders, :through => :traces, :source => :orders
  has_many :messages, :class_name => "Message", :foreign_key => "store_id"
  has_many :transactions, :through => :messages, :source => :transactions

  # scope :active, ->{ where.not(active_at:nil)}
end