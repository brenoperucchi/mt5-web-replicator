class Message::V2::Metatrader < Message::Message
  self.table_name = "messages"
  self.inheritance_column = :_type_disabled

  API_VERSION = "v2"


  state_machine :initial => :pending do
    # after_transition :pending => :executed, :do => lambda { |message| message.create_orders }
    # after_transition :pending => :executed, :do => lambda { |message| message.close_orders }
    event :execute do
        transition :pending => :executed
    end
    event :erro do
      transition [:pending, :executed] => :error
    end    
  end

  def close_orders(logging)
    account = Account.find_by(name: params_url("account_id"), kind: :copy)
    if params_copy("orders_closed").try(:present?)
      # params_copy = {imentore_copy: {orders_closed: params_copy("orders_closed")}}.merge(params_hash).to_json

      loggings.create(content:params_copy("orders_closed"), state: "ORDERS_CLOSED", changeset: account.name, account: account, parent:logging, resourceable: account)

      params_copy("orders_closed").each_with_index do |(ticket, copy_params), index|
        Transaction.where(ticket: ticket).each do |transaction|          
          transaction_closed(transaction, copy_params, logging, :orders_closed)
        end
      end
    end
    # logging = self.loggings.last
      
      if params_copy("orders_open").present?    
        account.transactions.executed.each do |transaction|
          ticket_id = transaction.ticket.to_s
          unless params_copy("orders_open").include?(ticket_id) 
            transaction_closed(transaction, params_copy("orders_closed")[ticket_id], logging, :orders_open) if params_copy("orders_closed").present? and params_copy("orders_closed")[ticket_id].present?
          end
        end        
      end

      account.transactions.executed.each do |transaction|
        ticket_id = transaction.ticket.to_s
        transaction_closed(transaction, params_copy("orders_closed")[ticket_id], logging, :orders_open) if params_copy("orders_closed").present? and params_copy("orders_closed")[ticket_id].present?
      end


    return true
  end

  def transaction_closed(transaction, copy_params, logging, kind)
    apiCopySerializerClass = Class.const_get("API::#{API_VERSION.try(:upcase)}::APICopySerializer")
    if transaction and transaction.can_close?
      # transaction.order.messages << self
      transaction.trace.messages << self
      transaction.attributes = apiCopySerializerClass.new(copy_params).closed_attributes
      transaction.save
      transaction.loggings.create(content:copy_params, state: "CLOSED", changeset: transaction.try(:versions).try(:last).try(:changeset), parent:logging, account: account, loggerable: self)
      transaction.update_mfe_mae(copy_params["mfe"], copy_params["mae"], copy_params["time_trader"]) 
      
      if not transaction.error?
        if transaction.close 
          transaction.slaves.each do |slave|
            slave.loggings.create(content: "Automatically remove by close_orders: #{kind} - #{transaction.id}", state: "REMOVE", account: slave.account, changeset: slave.try(:versions).try(:last).try(:changeset), parent:logging, loggerable: slave.order.messages.last)
          end
        end
      else
        transaction.slaves.executed.map(&:remove)
      end
    end

  end

  def create_orders(logging)    
    account = Account.find_by(name: params_url("account_id"), kind: :copy)
    if params_copy("orders_open").try(:present?) and account
      # TODO - Aceitar registro de message de copy mesmo se conta desabilitada 
      if account.enable?
        # params_copy = {imentore_copy: {orders_open: params_copy("orders_open")}}.merge(params_hash).to_json
        
        traces = account.traces.copy.active
        if traces.present? #and not content.blank? and content.is_a?(Hash)
          # message = Message::Metatrader.create(content: self.content, content_at: Time.zone.now, store: account.store, traces:traces)
          # TODO - Colocar uma trava se account estiver desabilitado

          # content = YAML.load(self.content)
          account_mode = params_url("account_mode")
          # account_copy = Account.find_by(name: params_url("account_id"))
          loggings.create(content:params_copy("orders_open"), state: "ORDERS_OPEN", changeset: account.name, account:  account, parent:logging, resourceable: account)
          changed = true

          params_copy("orders_open").each_with_index do |(ticket, copy_params), index|
            next if copy_params.empty?

            # copy_attributes = API::V220::APICopySerializer.new(copy_params).api_attributes
            state_meta = copy_params["state_meta"]
            traces.active.not_deleted.each do |trace|
              orders = trace.orders.where(content_id: ticket)
              # next if Order.where(content_id: ticket, account: account, trace: trace).take.present?

              unless orders.present? and account.try(:enable?)
                begin
                  self.traces << trace unless self.trace_ids.include?(trace.id)
                  trace.create_order(copy_params, account, self, copy_params["symbol"], API_VERSION) 
                rescue ActiveRecord::RecordNotUnique
                  self.loggings.create(content:"Duplicate Slave Ticket #{ticket} - Trace #{trace.id} #{trace.name} - Account #{account.name}", state: 'ERROR', resourceable: account, parent:self.loggings.last)
                end
              else             
                if orders.present?
                  self.loggings.first.update(state: "COPY/MODIFY")
                  orders.each do |order|
                    self.orders << order unless self.order_ids.include?(order.id)
                    self.traces << trace unless self.trace_ids.include?(trace.id)
                    order.transactions.each do|t|     
                      t.update_order_and_log(copy_params) if ["SLTPLOT", "PROFIT"].any?{|state| state_meta.try(:include?, state)}
                    end
                  end
                end
              end
            end
          end
        end
        return true
      else
        content_error = "Message::Metatrader ##{self.id} cannot executed - Account #{account.try(:id)} - Name #{account.try(:name)} disabled"
        loggings.create(content:content_error, state: "ERROR", changeset: self.try(:errors).try(:full_messages), account: account, parent:logging)
        return false
      end
    end
  end
end