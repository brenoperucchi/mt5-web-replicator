class Message::Metatrader < Message
  self.table_name = "messages"

  state_machine :initial => :pending do
    before_transition :pending => :prepared, :do => :update_state
    after_transition :prepared => :executed, :do => :update_state
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
        self.prepare_at = Time.current
      end
    end
    
    state :executed do
      def update_state(state)
        content = YAML.load(self.content)
        account_mode = content["params"]["account_mode"]
        account_copy = Account.find_by(name: content["params"]["account_id"])
        self.trace.accounts.slave.enable.each do |account|
          # Order All Closed
          if content['orders'].blank?
            account.slaves.where(state: ['pending', 'executed']).map(&:remove) if account.slaves

          ### Order Opened and Modify
          else
            account.slaves.executed.each do |slave|
              if content['orders'].flatten.detect{|x| x['order_id'].to_s == slave.ticket_master}
                next
              else
                slave.remove
              end
            end
          ### Order Opened and Modify
          # else
            content['orders'].flatten.group_by{|d|d['symbol']}.each_with_index do |(symbol, orders), index|
              if account.instrument_control.to_b
                instrument = account.instruments.find_by(symbol: symbol.try(:upcase)).try(:name)
              else 
                instrument = symbol
              end
              if account_mode == "HEDGING"
                orders.reverse.each do |order|
                  self.create_order(order, account, account_copy, symbol)
                  # # balance_order = account.orders.where(content_id: order['order_id']).try(:last)  
                  # balance_order = account.orders.find_by(content_id: order['order_id'])

                  # # transaction = balance_order.transactions.where(ticket: order['order_id']).try(:first)  
                  # api_transaction_attributes = SerializerAPITransaction.new(order).api_attributes.merge(symbol: instrument, profit:nil, message: self, trace: trace, account:account)
                  # if balance_order.nil?
                  #   balance_order = account.orders.create(message:self, trace: trace, content_id:api_transaction_attributes[:ticket], symbol: instrument, account:account)
                  # end
                  # @transaction = transactions.find_by(ticket: order['order_id'])
                  # if @transaction.nil?
                  #   @transaction = transactions.create(api_transaction_attributes)
                  # else
                  #     balance_order.transaction_ids = @transaction.id
                  # end
                  #   # deal = Deal.find_or_create_by(ticket: order['order_id'], symbol:instrument, account: account_copy, store: self.try(:store), trace:self.trace)
                  #   deal = Deal.create_with(ticket: order['order_id'], symbol:instrument, account: account_copy, store: self.try(:store), trace:self.trace).find_or_create_by(ticket: order['order_id'])
                  #   # master = Transaction.find_by(ticket: order['order_id'], deal:deal)
                  #   @transaction.update(deal: deal)
                                        
                  #   api_attributes = SerializerAPITransactionSlave.new(order).api_attributes.merge(symbol: instrument, price_request:@transaction.price_open, profit:nil, account:account, price_open:nil, price_closed:nil)
                  #   comment = api_attributes[:ticket_master]
                  #   # comment = "#{account.id}-#{transaction.id}-#{api_attributes[:ticket_master]}"
                  #   slave = balance_order.slaves.create(api_attributes.merge(symbol:instrument, comment: comment, account:account, master:@transaction, deal:deal))

                  #   @transaction.execute if @transaction.valid?
                  # if order['state_meta'] == "modify"
                  #   slave = balance_order.slaves.find_by(ticket_master: order['order_id'])
                  #   slave.update(take_profit:order['takeprofit'], stop_loss:order['stoploss'])
                  #   # behavior logging problem if update transaction slave lot 
                  #   # slave.update(lot: order['lot'], take_profit:order['takeprofit'], stop_loss:order['stoploss'])
                  # end
                end
              elsif account_mode == "NETTING" 
                balance_order = account.orders.where(symbol: instrument).where.not(state: :closed).try(:last)
                transaction = balance_order.transactions.where(symbol: instrument).where.not(state: :closed).try(:last) if balance_order
                # transaction = account.transactions.where(symbol: instrument).where.not(state: :closed).try(:last)
                if transaction.nil?
                  api_transaction_attributes = SerializerAPITransaction.new(orders.last).api_attributes.merge(symbol: instrument, profit:nil, message: self, trace: trace, account:account)
                  balance_order = account.orders.create(message:self, trace: trace, content_id:api_transaction_attributes[:ticket], symbol: instrument, account:account)
                  transaction = balance_order.transactions.create(api_transaction_attributes)
                end
                unless transaction.error?
                  orders.reverse.each do |order|
                    slave = transaction.slaves.find_by(ticket_master:order['order_id'])
                    unless slave
                      api_attributes = SerializerAPITransactionSlave.new(order).api_attributes.merge(symbol: instrument, price_request:transaction.price_open, profit:nil, account:account, price_open:nil)
                      comment = api_attributes[:ticket_master]
                      # comment = "#{account.id}-#{transaction.id}-#{api_attributes[:ticket_master]}"
                      balance_order.slaves.create(api_attributes.merge(symbol:instrument, comment: comment, account:account, master:transaction))
                      transaction.execute if transaction.valid?
                    else
                      slave.update(lot: order['lot'], take_profit:order['takeprofit'], stop_loss:order['stoploss']) if order['state_meta'] == "modify"
                    end
                  end
                end
              end
            end
          end
        end              
      end
    end
  end
end