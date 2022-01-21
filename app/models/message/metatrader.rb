class Message::Metatrader < Message
  self.table_name = "messages"

  state_machine :initial => :pending do
    # after_transition :pending => :prepared, :do => :restrictions
    before_transition :pending => :prepared, :do => :update_state
    after_transition :prepared => :executed, :do => :update_state
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
        self.prepare_at = Time.current
      end
    end
    
    state :executed do
      def update_state(state)
        content = YAML.load(Message.last.content)
        account_mode = content["params"]["account_mode"]
        self.trace.accounts.slave.each do |account|
          # Order All Closed
          if content['orders'].blank?
            account.slaves.map(&:remove) if account.slaves

          ### Order Opened and Modify
          elsif content['orders'].count < account.slaves.executed.count
            account.slaves.each do |slave|
              if content['orders'].flatten.detect{|x| x['order_id'].to_s == slave.ticket_master}
                next
              else
                slave.remove
              end
            end
          ### Order Opened and Modify
          else
            content['orders'].flatten.group_by{|d|d['symbol']}.each_with_index do |(symbol, orders), index|
              instrument = account.instruments.find_by(symbol: symbol.try(:upcase)).try(:name)
              if account_mode == "HEDGING"
                orders.reverse.each do |order|
                  transaction = account.transactions.where(ticket: order['order_id']).where.not(state: :closed).try(:last)  
                  if transaction.nil?
                    transaction = account.transactions.create(APITransactionSerializer.new(order).api_attributes.merge(symbol: instrument, state:'pending', profit:nil, message: self, trace: trace))
                    api_attributes = APITransactionSlaveSerializer.new(order).api_attributes.merge(symbol: instrument, state:'pending', price_request:transaction.price_open, profit:nil, account:account, price_open:nil)
                    comment = "#{account.id}-#{transaction.id}-#{api_attributes[:ticket_master]}"
                    transaction.slaves.create(api_attributes.merge(symbol:instrument, comment: comment, account:account))
                    transaction.execute
                  end
                end
              elsif account_mode == "NETTING" 
                transaction = account.transactions.where(symbol: instrument).where.not(state: :closed).try(:last)
                if transaction.nil?
                  transaction = account.transactions.create(APITransactionSerializer.new(orders.last).api_attributes.merge(symbol: instrument, state:'pending', profit:nil, message: self, trace: trace))
                end
                unless transaction.error?
                  orders.reverse.each do |order|
                    slave = transaction.slaves.find_by(ticket_master:order['order_id'])
                    unless slave
                      api_attributes = APITransactionSlaveSerializer.new(order).api_attributes.merge(symbol: instrument, state:'pending', price_request:transaction.price_open, profit:nil, account:account, price_open:nil)
                      comment = "#{account.id}-#{transaction.id}-#{api_attributes[:ticket_master]}"
                      transaction.slaves.create(api_attributes.merge(symbol:instrument, comment: comment, account:account))
                      transaction.execute
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
  #   state :prepared do
  #       def restrictions(state)
  #           action, new_value = self.message_action
  #           if restrict_order?(action) 
  #               if action == 'open_order'
  #                   self.create_order!
  #                   self.execute if order.message_action(action)
  #               else
  #                   orderr = root.order
  #                   self.execute if orderr.message_action(action, new_value)                        
  #               end
  #           else
  #               self.erro
  #           end
  #       end
  #   end
  # end

  # def restrict_order?(action)
  #   if action == 'open_order' 
  #       # if restrict_symbol? or restrict_time?
  #       # if restrict_nil_instrument? or restrict_symbol? or restrict_time? or not root? ##TODO - NEED A TESTING
  #       if restrict_time? or not root? ##TODO - NEED A TESTING
  #           # self.update_column(:response, "Order Restrict")   
  #           return false
  #       else
  #           return true
  #       end
  #   elsif action != 'open_order'
  #       if restrict_time? or (root.order.nil? and not root.order.try(:closed?))
  #           # self.update_column(:response, "Order Restrict")       
  #           return false
  #       else
  #           return true
  #       end
  #   elsif not action
  #       self.update_column(:response, "No Action")      
  #       return false
  #   else
  #       action
  #   end
  # end

  # def create_order!
  #   self.create_order(self.serializer.order_attributes) do |order|
  #       order.trace = self.trace
  #       order.content = self.content
  #   end
  #   order.prepare
  # end

  # def message_action
  #   action = self.serializer.action?
  # end

  # def root_message?
  #   self.ancestry.nil?
  # end

  # def restrict_time?
  #   if self.content_at + 20.minute < Time.current
  #       self.update_column(:response, "Restrict Time")      
  #       return true
  #   else
  #       return false
  #   end
  # end


  # # def restrict_nil_instrument?
  # #     if self.serializer.symbol.nil?
  # #         self.response = "Restrict Instrument"
  # #         return true
  # #     else
  # #         return false
  # #     end     
  # # end

# end