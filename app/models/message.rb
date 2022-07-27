require "ancestry"
class Message < ApplicationRecord
	has_ancestry
	
	has_many :orders, :class_name => "Order", :foreign_key => "message_id", dependent: :destroy
	has_many :transactions, through: :orders, source: :transactions,  dependent: :destroy
	# has_many :transactions, :class_name => "Transaction", :foreign_key => "message_id",  dependent: :destroy

	belongs_to :store, optional: true
	belongs_to :trace, optional: true	


	def create_order(order_params, account, account_copy, symbol)
	  order_attributes = order_params
	  if trace.copy_control_instrument.to_b
	  	instrument = trace.instruments.find_by(symbol: symbol.try(:upcase)).try(:name) || symbol
	  else
	  	instrument = account.instrument(symbol)
	  end
	  ticket = order_attributes['order_id']

	  order = store.orders.find_by(content_id: ticket, account:account)
 		serializer_attributes = SerializerAPITransaction.new(order_attributes).api_attributes.merge(symbol: symbol, profit:nil, message: self, trace: trace, account:account_copy) 	
	  if order.nil?
	  	order = store.orders.create(message:self, trace: trace, content_id:ticket, symbol: instrument, account:account)
	  end
	  transaction = Transaction.find_by(ticket: ticket)
	  if order.transactions.empty?
	  	if transaction.nil?
	  		transaction = order.transactions.create(serializer_attributes) 
	  		transaction.loggings.create(content:order_params, state: "OPEN")
	  	end
	  	transaction.balances.update(account:account_copy)
	  	order.transaction_ids = transaction.id
	  end
	  # transaction = order.transactions.create_with(serializer_attributes.merge(order:order, account:account_copy)).find_or_create_by(ticket: ticket)
	  # order.transaction_ids = transaction.id
	  # order.accounts << account
	  # order.account_ids = account.id
	  # transaction.account_ids = account_copy.id

    deal = Deal.create_with(ticket: ticket, symbol:instrument, account: account_copy, store: self.try(:store), trace:self.trace).find_or_create_by(ticket: ticket)
    transaction.update(deal: deal)
                        
    serializer_attributes_slave = SerializerAPITransactionSlave.new(order_attributes).api_attributes.merge(symbol: instrument, price_request:transaction.price_open, profit:nil, account:account, price_open:nil, price_closed:nil)
    comment = serializer_attributes_slave[:ticket_master]
    slave = order.slaves.create(serializer_attributes_slave.merge(symbol:instrument, comment: comment, account:account, master:transaction, deal:deal, trace: self.trace))
    slave.balances.update(account:account)

    transaction.execute if transaction.valid?
	  if order['state_meta'] == "modify"
  	  slave = balance_order.slaves.find_by(ticket_master: ticket)
    	slave.update(take_profit:order['takeprofit'], stop_loss:order['stoploss'])
  	end
	end

end