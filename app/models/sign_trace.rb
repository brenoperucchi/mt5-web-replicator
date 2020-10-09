class SignTrace < ApplicationRecord
	has_many :orders, :class_name => "SignOrder", :foreign_key => "sign_trace_id"
	has_many :slaves, :class_name => "SignSlave", :foreign_key => "sign_trace_id"

	# scope :ready, ->{ joins(:messages).where.not(:sign_messages => {ready_at:nil}) }
	scope :active, ->{ where.not(active_at:nil)}


end