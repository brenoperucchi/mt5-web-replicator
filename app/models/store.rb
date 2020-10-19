class Store < ApplicationRecord
	has_many :traces, :class_name => "Trace", :foreign_key => "store_id"
	store :settings, accessors: [ :lots ]

	scope :active, ->{ where.not(active_at:nil)}
end
