class ChangeMessageIdInSignOrdersToString < ActiveRecord::Migration[6.0]
	def self.up
	  change_table :sign_orders do |t|
	    t.change :message_id, :string
	  end
	end
	def self.down
	  change_table :sign_orders do |t|
	    t.change :message_id, :integer
	  end
	end
end