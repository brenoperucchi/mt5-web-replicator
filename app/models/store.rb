class Store < ApplicationRecord
  attr_accessor :restrict
  acts_as_taggable_on :tags

  has_many :traces, :class_name => "Trace", :foreign_key => "store_id"
  store :settings, accessors: [:master, :slaves]

  scope :active, ->{ where.not(active_at:nil)}
end