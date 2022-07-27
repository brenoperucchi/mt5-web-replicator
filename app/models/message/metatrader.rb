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
            account.slaves.where("transaction_slaves.trace_id = ?", trace.id).where(state: ['pending', 'executed']).map(&:remove) if account.slaves

          ### Order Opened and Modify
          else
            account.slaves.where("transaction_slaves.trace_id = ?", trace.id).executed.each do |slave|
              if content['orders'].flatten.detect{|x| x['order_id'].to_s == slave.ticket_master}
                next
              else
                slave.loggings.create(content: content['orders'], state: "REMOVE")
                slave.remove
              end
            end
          ### Order Opened and Modify
          # else
            content['orders'].flatten.group_by{|d|d['symbol']}.each_with_index do |(symbol, orders), index|
              if trace.copy_control_instrument.to_b
                instrument = account_copy.instruments.find_by(symbol: symbol.try(:upcase)).try(:name) || symbol
              elsif account.instrument_control.to_b
                instrument = account.instruments.find_by(symbol: symbol.try(:upcase)).try(:name) || symbol
              else 
                instrument = symbol
              end
              if account_mode == "HEDGING"
                orders.reverse.each do |order|
                  self.create_order(order, account, account_copy, symbol)
                end
              elsif account_mode == "NETTING" 
                balance_order = account.orders.where(symbol: instrument).where.not(state: :closed).try(:last)
                transaction = balance_order.transactions.where(symbol: instrument).where.not(state: :closed).try(:last) if balance_order
                # transaction = account.transactions.where(symbol: instrument).where.not(state: :closed).try(:last)
                if transaction.nil?
                  api_transaction_attributes = SerializerAPITransaction.new(orders.last).api_attributes.merge(symbol: symbol, profit:nil, message: self, trace: trace, account:account)
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