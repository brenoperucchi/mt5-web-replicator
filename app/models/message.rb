require "ancestry"
class Message < ApplicationRecord
	has_ancestry

	attr_accessor :new_value

 	has_one :order, :class_name => "Order", :foreign_key => "message_id"
 	has_many :transactions, :class_name => "Transaction", :foreign_key => "message_id"

	belongs_to :store, optional: true
	belongs_to :trace, optional: true
	
	scope :prepared, ->{ where(state: 'prepared')}
	# scope :action, ->{ where(state: 'action')}

	def serializer
		"Signals::#{"#{trace.name}Serializer".to_underscore.classify}".constantize.new(self)
	end

	state_machine :initial => :pending do
		after_transition :pending => :prepared, :do => :restrictions
		# after_transition :pending, :prepared] => :execute, :do => :restrictions
		event :prepare do
			transition :pending => :prepared
		end
		event :execute do
			transition :prepared => :executed
		end
		event :erro do
		  transition [:pending, :prepared, :executed] => :error
		end
		
		state :prepared do
			def restrictions(state)
				if restrict_symbol? and restrict_time? and message_action?
					action = self.message_action?
					if action != 'open_order'
						orderr = root.order
						orderr.new_value = self.new_value
						self.execute if orderr.message_action(action)
					elsif action == 'open_order'
						self.create_order!
						self.execute if order.message_action(action)
					end
					unless action
						self.erro
					else
						self.update_column(:prepare_at, DateTime.now)
					end
				else
					self.erro
				end
			end
		end
	end

	def create_order!
		self.create_order(self.serializer.order_attributes) do |order|
			order.trace = self.trace
			order.content = self.content
		end
		order.prepare
	end

	def message_action?
		# return if order.nil?
		action = self.serializer.action?
	end

	def root_message?
		self.ancestry.nil?
	end

	def restrict_time?
		if self.content_at + 15.minute > Time.now
			true
		else
			self.update_column(:response, "Restrict Time")		
			return false
		end
		
	end

	def restrict_symbol?
		if self.store.tag_list.map(&:downcase).include?(serializer.symbol.downcase)
	  	self.response = "Restrict Symbol"
	  	return false
	  else
	  	return true
	  end
	end

end