class Store < ApplicationRecord

  ENUMS = %w(state)
  include LibEnums

  store :settings, accessors: [:telegram_api_id, :telegram_api_number, :telegram_api_hash, :volume_default, :plan]
  enum state: {disable:0, enable:1, deleted:2}
  
  acts_as_taggable_on :tags

  has_many :accounts, :class_name => "Account", :foreign_key => "store_id", dependent: :destroy
  has_many :traces, :class_name => "Trace", :foreign_key => "store_id", dependent: :destroy
  has_many :orders, :through => :traces, :source => :orders, dependent: :destroy
  has_many :messages, :class_name => "Message", :foreign_key => "store_id"
  has_many :transactions, :through => :messages, :source => :transactions, dependent: :destroy
  has_many :users, dependent: :destroy
  has_many :customers, dependent: :destroy
  has_many :invoices, :through => :customers, :source => :invoices

  validates_presence_of :plan, :on => :create

  accepts_nested_attributes_for :customers, :users

  # scope :active, ->{ where.not(active_at:nil)}
end