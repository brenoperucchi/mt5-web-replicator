module Model
  class TraceService

    attr_accessor :trace, :order_params, :account, :message, :symbol, :api_version

    def initialize(trace, order_params, account, message, symbol, api_version)
      @trace        = trace
      @order_params = order_params
      @account      = account
      @message      = message
      @symbol       = symbol
      @api_version  = api_version
    end

    def create_order
      copySerializer = Class.const_get("API::#{api_version.try(:upcase)}::CopySerializer").new(order_params)
      
      instrument = check_instrument(account, symbol)
        
      copy_attributes = copySerializer.copy_attributes.merge(symbol: instrument, message: message, trace: trace, account:account)
      ticket = copySerializer.ticket

      trace.stores.each do |current_store|
        account_slaves = trace.accounts.slave.enable.where(store: current_store)
        next unless account_slaves.present?
        if account.netting?
          order = account.orders.where(symbol: instrument).where.not(state: [:closed, :pending]).try(:last)
          if order.nil?
            order = account.orders.create(messages: [message], message: message, trace: trace, content_id: ticket, symbol: instrument, account:account, store:current_store) 
          end
          transaction = Transaction.find_by(symbol: instrument, account: account, trace:trace)
          transaction ||= Transaction.create(copy_attributes.merge(account:account))
        elsif account.hedging?
          order = Order.create_with(trace: trace, messages: [message], message: message, content_id: ticket, symbol:instrument, account: account, store: current_store).find_or_create_by(content_id: ticket, trace:trace, store: current_store)
          # order = account.orders.create_with(trace: supelf, messages: [message], message: message, content_id: ticket, symbol:instrument, account: account, store: account.try(:store)).find_or_create_by(content_id: ticket, trace:trace)
          transaction = Transaction.create_with(copy_attributes).find_or_create_by(ticket: ticket)
        end
        if transaction.valid?
          transaction.traces << trace unless transaction.traces.exists?(trace.id)
          transaction.orders << order unless transaction.orders.exists?(order.id)
          account.orders << order unless account.orders.exists?(order.id)
        else
          if order.present?
            content_msg = "Error create Transaction - Order #{order.id} - Account #{account_slave.id}"
            message.loggings.create(content: content_msg, changeset: transaction.try(:versions).try(:last).try(:changeset), state: "ERROR", parent: message.loggings.first, account: account, resourceable:order, request_url: message.try(:request_url))
          else
            content_msg = "Error create Transaction - Account #{account_slave.id}"
            message.loggings.create(content: content_msg, changeset: transaction.try(:versions).try(:last).try(:changeset), state: "ERROR", parent: message.loggings.first, account: account, request_url: message.try(:request_url))
          end
        end

        transaction.update_mfe_mae(copySerializer) 
        
        if order.valid?
          order.execute
        end
          
        if order.valid? and not order.error?
          transaction.loggings.create(loggerable:message, content:order_params, changeset: transaction.try(:versions).try(:last).try(:changeset), state: "OPEN", parent: message.loggings.first, account: account, request_url: message.try(:request_url))
          transaction.execute unless transaction.executed?
          # if transaction and not transaction.error?
          if transaction and !TradeHelperService.resource_restricted?(transaction, trace) and not TradeHelperService.resource_restricted?(transaction, account) 
            return true if account.netting? and order.slaves.count > 0 
            account_slaves.each do |account_slave|
              instrument = check_instrument(account, symbol, account_slave)
              serializer = "API::#{api_version.try(:upcase)}::SlaveSerializer".classify.safe_constantize.new(order_params, trace: trace)
              serializer.comment = "#{trace.id}-#{ticket}"
              
              slave_attributes = serializer.trace_attributes(instrument, account_slave, transaction, trace, current_store)            
              slave = order.slaves.new(slave_attributes.merge(position_id:nil, ticket_deal:nil, ticket_master: ticket))
              slave.magic_number = check_magic_number(slave_attributes[:magic_number])
              if trace.prop_firm?
                slave.comment      = "#{account_slave.id}#{slave.magic_number}_#{slave.comment}"
                slave.magic_number = "#{account_slave.id}#{slave.magic_number}".to_i
              end
              if slave.save
                account_slave.orders << order unless account_slave.orders.exists?(order.id) 
                slave.loggings.create(loggerable:message, content:order_params, changeset: slave.try(:versions).try(:last).try(:changeset), state: "CREATE", parent: message.loggings.first, account: account_slave, request_url: message.try(:request_url))
              else
                message.loggings.create(content: "Error create Slave - Order #{order.id} - Account #{account_slave.id}", changeset: transaction.try(:versions).try(:last).try(:changeset), state: "ERROR", parent: message.loggings.first, account: account, resourceable:order, request_url: message.try(:request_url))
              end
            end
          end
        end
      end
    end

    def check_magic_number(magic_number)
      trace.magic_same.to_b ? magic_number : trace.name_id
    end

    def check_instrument(account, symbol, account_slave=nil)
      if account_slave and trace.instrument_control.to_b
        instrument = account_slave.instruments.find_by(symbol: symbol.try(:upcase)).try(:name) if account_slave.instrument_control.to_b
        instrument ||= account.instruments.find_by(symbol: symbol.try(:upcase)).try(:name) if account.instrument_control.to_b
      end
      instrument || symbol
    end
  end
end