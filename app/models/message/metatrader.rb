class Message::Metatrader < Message::Message
  self.table_name = "messages"

  state_machine :initial => :pending do
    after_transition :pending => :executed, :do => lambda { |message| message.create_orders }
    after_transition :pending => :executed, :do => lambda { |message| message.close_orders }
    event :execute do
        transition :pending => :executed
    end
    event :erro do
      transition [:pending, :executed] => :error
    end    
  end

  def close_orders
    content = YAML.load(self.content)
    self.traces.each do |trace|
      # Close All Orders
      if content['orders'].blank?
        trace.transactions.pending_executed.each do |transaction|
          transaction.close
          transaction.close_info
          transaction.loggings.create(content: "Remove automatically by Close Orders Blank #{transaction.id}", state: "CLOSED_INFO", resourceable:self, changeset: transaction.try(:versions).try(:last).try(:changeset))
        end
      else
        trace.transactions.pending_executed.each do |transaction|
          unless content['orders'].flatten.detect{|x| x['ticket_id'].to_s == transaction.ticket}
            transaction.close
            transaction.close_info
            transaction.loggings.create(content: "Remove automatically by Close Orders #{transaction.id}", state: "CLOSED_INFO", resourceable:self, changeset: transaction.try(:versions).try(:last).try(:changeset))
          end
        end      
      end
    end
  end

    # if content['orders'].blank?
    #   self.trace.slaves.pending_executed.map(&:remove)
    
    # # Close Specify Order
    # else
    #   self.trace.slaves.pending_executed.each do |slave|
    #     if content['orders'].flatten.detect{|x| x['order_id'].to_s == slave.ticket_master}
    #       # next
    #     else
    #       if slave.remove
    #         slave.loggings.create(content: "Remove Automatically by MessageMetaTrader#{self.id} \r\n Content-> #{content['orders']}", state: "REMOVE") 
    #       end
    #     end
    #   end
    # end
  # end

  def create_orders
    yaml_content = YAML.load(self.content)
    account_mode = yaml_content["params"]["account_mode"]
    account_copy = Account.find_by(name: yaml_content["params"]["account_id"])
    
    yaml_content['orders'].flatten.group_by{|d|d['symbol']}.each_with_index do |(symbol, orders), index|
      orders.reverse.each do |order_params|
        ticket = order_params['ticket_id']
        
        # orders = self.trace.orders.where(content_id: ticket, state: :executed)
        self.traces.each do |trace|
          orders = trace.orders.where(content_id: ticket)
          if not order_params['state_meta'].present?
            unless orders.present?
              trace.create_orders(order_params, account_copy, self, symbol)
            end
          elsif order_params['state_meta'] == "modify"
            orders.each do |order| 
              order.transactions.map{|t| t.set_lot_sl_tp(order_params) }
            end
          end
        end
      end
    end
  end

  # def order_netting(order_params, account, account_copy, symbol)
  #   order = account.orders.where(symbol: symbol, account:account).where.not(state: :closed).try(:last)
  #   transaction = order.transactions.where(symbol: symbol, account:account).where.not(state: :closed).try(:last) if order
    
  #   # transaction = account.transactions.where(symbol: symbol).where.not(state: :closed).try(:last)
  #   # -g.pry
  #   if transaction.nil?
  #     api_transaction_attributes = SerializerAPITransaction.new(order_params).api_attributes.merge(symbol: symbol, profit:nil, message: self, trace: trace, account:account)
      
  #     order = account.orders.create(message:self, trace: trace, content_id:api_transaction_attributes[:ticket], symbol: symbol, account:account, store:self.store) 
  #     order.execute
  #     transaction   = order.transactions.create(api_transaction_attributes)
  #     transaction.loggings.create(content:order_params, state: "OPEN")
  #   end
  #   unless order.error?
  #     slave = account.slaves.find_by(ticket_master:order_params['order_id'])
  #     if slave.nil?
  #       api_attributes = SerializerAPITransactionSlave.new(order_params).api_attributes.merge(symbol: symbol, price_request:order_params['price'], profit:nil, account:account, price_open:nil)
  #       comment = api_attributes[:ticket_master]
  #       # comment = "#{account.id}-#{transaction.id}-#{api_attributes[:ticket_master]}"
  #       slave = order.slaves.create(api_attributes.merge(symbol:symbol, comment: comment, account:account, master:transaction, trace:self.trace))
  #       # slave.balances.update(account:account)

  #       transaction.execute if transaction.valid?
  #     else
  #       if order_params['state_meta'] == "modify"
  #         transaction.set_lot_sl_tp(order_params["volume"], order_params['take_profit'].to_f, order_params['stop_loss'].to_f)
  #         # transaction.update(lot: order_params['volume'], take_profit:order_params['take_profit'].to_f, stop_loss:order_params['stop_loss'].to_f)
  #         @version = transaction.versions.last
  #         transaction.loggings.create(content:order_params, changeset: @version.changeset, version:@version, state: 'MODIFY')
  #         slave.update(lot: order_params['volume'], take_profit:order_params['take_profit'].to_f, stop_loss:order_params['stop_loss'].to_f) 
  #       end
  #       # @version = @slave.versions.last
  #       # slave.loggings.create(content:order_params, changeset: @version.changeset, version:@version, state: 'MODIFY')

  #     end
  #   end
  # end

  # def order_hedging(order_params, account, account_copy, symbol)
  #   if trace.instrument_control.to_b
  #     instrument = trace.instruments.find_by(symbol: symbol.try(:upcase)).try(:name) || symbol
  #   else
  #     instrument = account.instrument(symbol)
  #   end
  #   ticket = order_params['order_id']

  #   order = store.orders.find_by(content_id: ticket, account:account)
  #   serializer_attributes = SerializerAPITransaction.new(order_params).api_attributes.merge(symbol: symbol, profit:nil, message: self, trace: trace, account:account_copy)  
  #   if order.nil?
  #     order = store.orders.create(message:self, trace: trace, content_id:ticket, symbol: instrument, account:account)
  #     order.execute
  #   end
  #   transaction = Transaction.find_by(ticket: ticket)
  #   if order.transactions.empty?
  #     if transaction.nil?
  #       transaction = order.transactions.create(serializer_attributes) 
  #       transaction.loggings.create(content:order_params, state: "OPEN")
  #     end
  #     order.transaction_ids = transaction.id
  #   transaction.balances.update(account:account_copy)
  #   end

  #   deal = Deal.create_with(ticket: ticket, symbol:instrument, account: account_copy, store: self.try(:store), trace:self.trace).find_or_create_by(ticket: ticket)
  #   transaction.update(deal: deal)
                        
  #   serializer_attributes_slave = SerializerAPITransactionSlave.new(order_params).api_attributes.merge(symbol: instrument, price_request:transaction.price_open, profit:nil, account:account, price_open:nil, price_closed:nil)
  #   comment = serializer_attributes_slave[:ticket_master]
  #   slave = order.slaves.create(serializer_attributes_slave.merge(symbol:instrument, comment: comment, account:account, master:transaction, deal:deal, trace: self.trace))

  #   slave.balances.update(account:account)

  #   transaction.execute if transaction.valid?
  #   if order_params['state_meta'] == "modify"
  #     transaction.set_lot_sl_tp(order_params["volume"], order_params['take_profit'].to_f, order_params['stop_loss'].to_f)
  #     slave = order.slaves.find_by(ticket_master: ticket)
  #     slave.update(take_profit:order_params['take_profit'].to_f, stop_loss:order_params['stop_loss'].to_f)
  #   end
  # end
end