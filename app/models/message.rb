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
	  # message_id = attributes[:message_id]
	  # account_id = attributes[:account_id]
	  instrument = account.instrument(symbol)
	  ticket = order_attributes['order_id']

	  order = account.orders.find_by(content_id: ticket)
 		serializer_attributes = SerializerAPITransaction.new(order_attributes).api_attributes.merge(symbol: instrument, profit:nil, message: self, trace: trace, account_id:account_id) 	
	  if order.nil?
	  	order = account.orders.create(message:self, trace: trace, content_id:ticket, symbol: instrument, account:account)
	  end
	  transaction = Transaction.create_with(serializer_attributes.merge(order:order)).find_or_create_by(ticket: ticket)
	  order.transaction_ids = transaction.id

    deal = Deal.create_with(ticket: ticket, symbol:instrument, account: account_copy, store: self.try(:store), trace:self.trace).find_or_create_by(ticket: ticket)
    transaction.update(deal: deal)
                        
    serializer_attributes_slave = SerializerAPITransactionSlave.new(order_attributes).api_attributes.merge(symbol: instrument, price_request:transaction.price_open, profit:nil, account:account, price_open:nil, price_closed:nil)
    comment = serializer_attributes_slave[:ticket_master]
    slave = order.slaves.create(serializer_attributes_slave.merge(symbol:instrument, comment: comment, account:account, master:transaction, deal:deal))

    transaction.execute if transaction.valid?
	  if order['state_meta'] == "modify"
  	  slave = balance_order.slaves.find_by(ticket_master: ticket)
    	slave.update(take_profit:order['takeprofit'], stop_loss:order['stoploss'])
  	end
	end

end