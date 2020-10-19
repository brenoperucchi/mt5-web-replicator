class ChangeMessageIdInOrdersToString < ActiveRecord::Migration[6.0]
	def self.up
	  change_table :orders do |t|
	    t.change :message_id, :string
	  end
	end
	def self.down
	  change_table :orders do |t|
	    t.change :message_id, :integer
	  end
	end
end