class TransactionSlave < ApplicationRecord

	enum state: {pending:0, executed:1, remove:2, closed:3, deleted:4}

	has_many :loggings, as: :loggerable
	
	belongs_to :transaction_master, :class_name => "Transaction", :foreign_key => "transaction_id"
	
	has_one :account,		through: :transaction_master, source: :account#, source_type:'Account'

	# scope :pending, 	->{where(state: 'pending')}
	# scope :executed, 	->{where(state: 'executed')}
	# scope :remove, 	 	->{where(state: 'remove')}
	scope :opened, 	 	->{where(state: [:pending, :executed])}
	scope :entire, 	 	->{where(state: [:pending, :executed, :remove, :deleted, :closed])}

	validates_presence_of :symbol

	def meta_attributes(value=0)
	  openprice = (ordertype == "0" or ordertype == 1) ? "0" : price_request
	  instrument = transaction_master.order.trace.instruments.find_by_symbol(symbol)
	  @meta_attributes = { 
	    instrument: symbol,
	    ordertype: ordertype,
	    volume:self.lot,
	    openprice: openprice,
	    slippage:10,
	    magic_number: self.magic_number.to_i.abs,
	    stoploss: stop_loss,
	    takeprofit: take_profit,
	    trace_id: transaction_master.order.trace.id,
	    transaction_id: self.id,
	    ticket: self.ticket
	  }
	end

	def api_request_attributes
		# instrument = transaction_master.order.trace.instruments.find_by_symbol(symbol)
		openprice = (ordertype == "0" or ordertype == 1) ? "0" : price_request
		msg = "#{ordertype}|#{ticket}|#{transaction_master.try(:order).try(:trace).try(:id)}|#{self.id}|#{self.magic_number}|#{transaction_master.id}|#{openprice}|#{lot}|#{stop_loss}|#{take_profit}|#{state}|#{symbol}|#{comment}|"
		return msg
	end
end