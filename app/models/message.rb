require "ancestry"
class Message < ApplicationRecord
 	has_one :order, :class_name => "Order", :foreign_key => "message_id"
 	has_many :transactions, :class_name => "Transaction", :foreign_key => "message_id"

	belongs_to :store, optional: true
	belongs_to :trace, optional: true
	
	has_ancestry

	scope :prepared, ->{ where(state: 'prepared')}

	def serializer
		"Signals::#{"#{trace.name}Serializer".to_underscore.classify}".constantize.new(self)
	end

	state_machine :initial => :pending do
		after_transition :pending => :prepared, :do => :restrictions
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
				if restrict_symbol? and restrict_time? and prepare?
					self.update_column(:prepare_at, DateTime.now)
				else
					self.erro
				end
			end
		end
	end

	def prepare?
		serializer.prepare? ? true : false
	end

	def restrict_time?
		if self.content_at + 5.minute > Time.now
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