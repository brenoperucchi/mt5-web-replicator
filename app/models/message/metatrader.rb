class Message::Metatrader < Message::Message
  self.table_name = "messages"
  self.inheritance_column = :_type_disabled


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

  #   def all_loggings
  #   loggings.or(Logging.where(id:logging_orders))
  # end

  def close_orders
    yaml_content = YAML.load(self.content)
    account_copy = Account.find_by(name: yaml_content["params"]["account_id"])
    self.traces.each do |trace|

      # Close All Orders
      if yaml_content['orders'].blank?
        trace.masters.where(account:account_copy).pending_executed.each do |transaction|
          transaction.close
          transaction.close_info
          transaction.loggings.create(content: "Remove automatically by Close Orders Blank #{transaction.id}", state: "CLOSED_INFO", resourceable:self, changeset: transaction.try(:versions).try(:last).try(:changeset))
        end
      else
        trace.masters.where(account:account_copy).pending_executed.each do |transaction|
          unless yaml_content['orders'].flatten.detect{|x| x['ticket_id'].to_i == transaction.ticket.to_i}
            transaction.close
            transaction.close_info
            transaction.loggings.create(content: "Remove automatically by Close Orders #{transaction.id}", state: "CLOSED_INFO", resourceable:self, changeset: transaction.try(:versions).try(:last).try(:changeset))
          end
        end      
      end
    end
  end

  def create_orders
    yaml_content = YAML.load(self.content)
    account_mode = yaml_content["params"]["account_mode"]
    account_copy = Account.find_by(name: yaml_content["params"]["account_id"])
    
    yaml_content['orders'].flatten.group_by{|d|d['symbol']}.each_with_index do |(symbol, orders), index|
      orders.reverse.each do |order_params|
        ticket = order_params['ticket_id']
        
        # orders = self.trace.orders.where(content_id: ticket, state: :executed)
        self.traces.active.not_deleted.each do |trace|
          api_transaction = SerializerAPITransaction.new(order_params)
          orders = trace.orders.where(content_id: ticket)
          if not order_params['state_meta'].present?
            unless orders.present?
              trace.create_order(order_params, account_copy, self, symbol, "v2")
            end
          elsif order_params['state_meta'] == "modify"
            orders.each do |order|
              unless order.error? 
                order.transactions.each do|t| 
                  t.set_lot_sl_tp(order_params) 
                  t.set_mfe_mae(api_transaction.mfe, api_transaction.mae, api_transaction.time_trader)
                end
              end
            end
          elsif order_params['state_meta'] == "modify_profit"
            orders.each do |order| 
              unless order.error? 
                order.transactions.each do |t| 
                  t.set_profit(order_params['profit'])
                  t.set_mfe_mae(api_transaction.mfe, api_transaction.mae, api_transaction.time_trader)
                end
              end
            end
          end
        end
      end
    end
  end
end