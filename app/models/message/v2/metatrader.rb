class Message::V2::Metatrader < Message::Message
  self.table_name = "messages"
  self.inheritance_column = :_type_disabled

  API_VERSION = "v2"


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
    if params_copy["orders_closed"].present?
      # params_copy = {imentore_copy: {orders_closed: params_copy["orders_closed"]}}.merge(params_hash).to_json

      account = Account.find_by(name: params_url["account_id"], kind: :copy)
      loggings.create(content:params_copy, state: "ORDERS_CLOSED", changeset: account.name, account: account, parent:all_loggings.first)
      
      params_copy["orders_closed"].each_with_index do |(ticket, copy_params), index|
        Transaction.where(ticket: ticket).each do |transaction|
          if transaction and not transaction.closed?
            transaction.attributes = {price_closed:  copy_params["price_closed"], profit: copy_params["profit"], closed_at:copy_params["close_at"]}
            transaction.save
            transaction.loggings.create(content:copy_params, state: "CLOSED", changeset: transaction.try(:versions).try(:last).try(:changeset), parent:all_loggings.first)
            transaction.set_mfe_mae(copy_params["mfe"], copy_params["mae"], copy_params["time_trader"]) 
            
            # if transaction.can_close?
              if transaction.close 
                
                transaction.slaves.each do |slave|
                  slave.loggings.create(content: "Remove automatically by Close Orders #{transaction.id}", state: "CLOSED_INFO", account: account, changeset: transaction.try(:versions).try(:last).try(:changeset), parent:all_loggings.first)
                end
              else
                changed = false
              end
            # end
          end
        end
      end
    end
  end

  def create_orders    
    if params_copy["orders_open"].present?
      # TODO - Aceitar registro de message de copy mesmo se conta desabilitada 
      account = Account.find_by(name: params_url["account_id"], kind: :copy)
      if account and account.enable?
        # params_copy = {imentore_copy: {orders_open: params_copy["orders_open"]}}.merge(params_hash).to_json
        
        traces = account.traces.copy.active
        if traces.present? #and not content.blank? and content.is_a?(Hash)
          self.traces << traces
          # message = Message::Metatrader.create(content: self.content, content_at: Time.zone.now, store: account.store, traces:traces)
          # TODO - Colocar uma trava se account estiver desabilitado

          # content = YAML.load(self.content)
          account_mode = params_url["account_mode"]
          # account_copy = Account.find_by(name: params_url["account_id"])
          loggings.create(content:params_copy, state: "ORDERS_OPEN", changeset: account.name, account:  account, parent:all_loggings.first)
          changed = true

          params_copy["orders_open"].each_with_index do |(ticket, copy_params), index|



            # copy_attributes = API::V220::APICopySerializer.new(copy_params).api_attributes
            state_meta = copy_params["state_meta"]
            traces.active.not_deleted.each do |trace|
              orders = trace.orders.where(content_id: ticket)
              unless orders.present?
                if trace.create_order(copy_params, account, self, copy_params["symbol"], API_VERSION) 
                  changed ||= false
                end
              else
                if orders.present? and state_meta.try(:include?, "SLTPLOT")
                  orders.each do |order| 
                    order.transactions.each do|t| 
                      t.set_lot_sl_tp(copy_params) 
                      t.set_mfe_mae(copy_params["mfe"], copy_params["mae"], copy_params["time_trader"])
                    end
                  end
                end
                if orders.present? and state_meta.try(:include?, "PROFIT")
                  orders.each do |order| 
                    order.transactions.each do |t| 
                      t.set_profit(copy_params)
                      t.set_mfe_mae(copy_params["mfe"], copy_params["mae"], copy_params["time_trader"])
                    end
                  end
                end
              end
            end

          end
        end
      end
    else
      content_error = "Message::Metatrader ##{self.id} cannot executed - Account Name #{account.try(:name)}"
      loggings.create(content:content_error, state: "ERROR", changeset: self.try(:errors).try(:full_messages), account: account, parent:all_loggings.first)
    end
  end
end