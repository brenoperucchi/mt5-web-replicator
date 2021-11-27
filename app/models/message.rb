require "ancestry"
class Message < ApplicationRecord
	has_ancestry

	# attr_accessor :new_value

 	has_one :order, :class_name => "Order", :foreign_key => "message_id", dependent: :destroy
 	has_many :transactions, :class_name => "Transaction", :foreign_key => "message_id",  dependent: :destroy

	belongs_to :store, optional: true
	belongs_to :trace, optional: true
	
	scope :prepared, ->{ where(state: 'prepared')}
	scope :executed, ->{ where(state: 'executed')}
	# scope :action, ->{ where(state: 'action')}

	def serializer
		"Signals::#{"#{trace.name}Serializer".to_underscore.classify}".constantize.new(self)
	end

	state_machine :initial => :pending do
		after_transition :pending => :prepared, :do => :restrictions
		before_transition :pending => :prepared, :do => :update_state
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
		
		state :pending do
			def update_state(state)
				self.prepare_at = DateTime.now
			end
		end
		state :prepared do
			def restrictions(state)
				action, new_value = self.message_action
				if restrict_order?(action) 
					if action == 'open_order'
						self.create_order!
						self.execute if order.message_action(action)
					else
						orderr = root.order
						self.execute if orderr.message_action(action, new_value)						
					end
				else
					self.erro
				end
			end
		end
	end

	def restrict_order?(action)
		if action == 'open_order' 
			# if restrict_symbol? or restrict_time?
			if restrict_nil_instrument? or restrict_symbol? or restrict_time? or not root? ##TODO - NEED A TESTING
				# self.update_column(:response, "Order Restrict")	
				return false
			else
				return true
			end
		elsif action != 'open_order'
			if restrict_time? or (root.order.nil? and not root.order.try(:closed?))
				# self.update_column(:response, "Order Restrict")		
				return false
			else
				return true
			end
		elsif not action
			self.update_column(:response, "No Action")		
			return false
		else
			action
		end
	end

	def create_order!
		self.create_order(self.serializer.order_attributes) do |order|
			order.trace = self.trace
			order.content = self.content
		end
		order.prepare
	end

	def message_action
		action = self.serializer.action?
	end

	def root_message?
		self.ancestry.nil?
	end

	def restrict_time?
		if self.created_at + 15.minute < DateTime.now
			self.update_column(:response, "Restrict Time")		
			return true
		else
			return false
		end
	end

	def restrict_symbol?
		if self.store.tag_list.map(&:downcase).include?(serializer.symbol.downcase)
	  		self.response = "Restrict Symbol"
	  		return true
	  	else
	  		return false
	  	end
	end

	def restrict_nil_instrument?
		if self.serializer.symbol.nil?
	  		self.response = "Restrict Instrument"
	  		return true
	  	else
	  		return false
	  	end		
	end

end