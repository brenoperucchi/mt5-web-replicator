class Store < ApplicationRecord
	has_many :traces, :class_name => "SignTrace", :foreign_key => "store_id"

	scope :active, ->{ where.not(active_at:nil)}
end
