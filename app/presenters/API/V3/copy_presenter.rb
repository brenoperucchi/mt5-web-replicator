class API::V3::CopyPresenter < API::V3::BasePresenter

  API_VERSION = "v3"

  attr_accessor :message, :account

  def initialize(params, message, account)
    @params = params
    @message = message
    @account = account
  end

  def opening(jsons = nil, state = "COPY/OPEN")
    jsons  ||= positionOrders
    if jsons.present?
      logging = message.loggings.create(content: jsons, state: state, changeset: account.name, account: account, request_url: message.request_url, params: params, resourceable: account.store)       
      traces = account.traces.copy.active
      if traces.present?
        changed = true
        jsons.each do |json|
          next if json.empty?

          next if (state == "COPY/PENDING") and (json['type'].to_i < 2) # TODO MELHORAR ISTO! SE NÃO CRIAR NADA CRIAR UM REGISTRO NO LOG

          # state_meta = json["state_meta"]
          traces.active.not_deleted.each do |trace|
            @orders = trace.orders.where(content_id: json["ticketMaster"], account: account)
            if not @orders.present?
              begin
                message.traces << trace unless message.trace_ids.include?(trace.id)
                trace_service = Model::TraceService.new(trace, json, account, message, json["symbol"], API_VERSION)
                # unless trace.create_order(json, account, message, json["symbol"], API_VERSION) 
                unless trace_service.create_order
                  message.loggings.create(content:"Error create_order - Trace #{trace.id} #{trace.name} - Trace Errors #{trace.try(:errors).try(:full_messages)} - Account #{account.name}", state: 'ERROR', resourceable: account, parent:message.loggings.last)
                end
              rescue ActiveRecord::RecordNotUnique
                message.loggings.create(content:"RecordNotUnique - Duplicate Slave Ticket #{json["ticketMaster"]} - Trace #{trace.id} #{trace.name} - Account #{account.name}", state: 'ERROR', resourceable: account, parent:message.loggings.last)
              rescue Exception => e
                message.loggings.create(content:"Error create_order - Trace #{trace.id} #{trace.name} - Trace Errors #{e.message} - Account #{account.name}", state: 'ERROR', resourceable: account, parent:message.loggings.last)
              end
            elsif @orders.present? 
              @orders.each do |order|
                order.transactions.each do |transaction|
                  serializer = API::V3::CopySerializer.new(json)
                  if transaction.stop_loss.try(:to_f) != serializer.stop_loss or transaction.take_profit.try(:to_f) != serializer.take_profit or transaction.profit.try(:to_f) != serializer.profit or transaction.price_open.try(:to_f) != serializer.price_open
                    message.orders << order unless message.order_ids.include?(order.id)
                    message.traces << trace unless message.trace_ids.include?(trace.id)
                    if transaction.update_modify_meta(serializer)
                      # transaction.update_slaves(serializer)
                      transaction.update_mfe_mae(serializer)
                      version = transaction.try(:versions).try(:last)
                      transaction.loggings.create(content: serializer.obj, changeset: version.changeset, version: version, state: "MODIFY", resourceable: order, account: account, parent: message.loggings.try(:first), request_url: message.try(:request_url), loggerable: message)
                    end 
                  end
                end
              end
            end
          end
        end
        return true
      else
        content_error = "Message::Metatrader ##{message.id} cannot executed - Account #{account.try(:id)} - Name #{account.try(:name)} disabled"
        message.loggings.create(content:content_error, state: "ERROR", changeset: message.try(:errors).try(:full_messages), account: account, parent: message.loggings.first)
        return false
      end
    end
  end

  def pending
    self.opening(pendingOrders, "COPY/PENDING")
    if pendingOrders.present?
      logging = message.loggings.create(content: pendingOrders, state: "COPY/PENDING", changeset: account.name, account: account, request_url: message.request_url, params: params)             
      transactions = Transaction.executed.where(ordertype: [2..], account: account)
      transactions.each do |transaction|
        pending  = pendingOrders.detect{|json| json["ticketMaster"] == transaction.ticket} 
        position = positionOrders.detect{|json| json["ticketMaster"] == transaction.ticket} 
        if not pending and not position
          if transaction.close
            transaction.close_slaves
          end
        end
      end
    end
    if pendingOrders.blank?
      transactions = Transaction.executed.where(ordertype: [2..], account: account)
      transactions.each do |transaction| 
        unless positionOrders.detect{|json| json["ticketMaster"] == transaction.ticket} 
          transaction.close_slaves if transaction.close
        end
      end
    end
  end

  # Processes transaction closings for copy trading
  #
  # This method handles the closing of transactions related to copy trading:
  # 1. First logs the closing action with the message and account information
  # 2. Then processes closings through three sequential mechanisms:
  #
  # @return [Boolean] Returns true when all closings have been processed
  def closing
    # Log the closing action with account information
    message.loggings.create(content:message.content, state: "COPY/CLOSE", changeset: account.name, account: account, request_url: message.request_url, params: params)        
    
    if account
      # CLOSING MECHANISM 1:
      # Process transactions found in history but not in current positions
      # Closes any executed or pending-close transactions that aren't in the active positions list
      historyOrders.each do |json|
        transactions = Transaction.executed.where(ticket: json["ticketMaster"], account: account)
        transactions += Transaction.closed.where(ticket: json["ticketMaster"], account: account, closed_at: nil)          
        transactions.uniq.each do |transaction|
          position = positionOrders.detect{|json| json["ticketMaster"] == transaction.ticket} 
          if position.blank?
            transaction_closed(transaction, json, :copy_close)
          end
        end
      end
    end
      
    if positionOrders.present?    
      # CLOSING MECHANISM 2:
      # Process executed transactions that are not in the current positions list
      # Ensures any transactions that were executed but no longer appear in positions are closed
      account.transactions.executed.each do |transaction|
        unless positionOrders.detect{|json| json["ticketMaster"] == transaction.ticket} 
          order_params = historyOrders.detect{|json| json["ticketMaster"] == transaction.ticket} || {}
          transaction_closed(transaction, order_params, :copy_close) if order_params.present?
        end
      end        
    end

    # # CLOSING MECHANISM 3:
    # # Process all remaining executed transactions that match positions
    # # Final pass to ensure all transactions are properly closed based on latest data
    # account.transactions.executed.each do |transaction|
    #   if historyOrders.detect{|json| json["ticketMaster"] == transaction.ticket} 
    #     order_params = historyOrders.detect{|json| json["ticketMaster"] == transaction.ticket} || {}
    #     transaction_closed(transaction, order_params, :copy_close) if order_params.present?
    #   end
    # end
    
    # # ——— Mecanismos 2 e 3 unificados ———
    # # fecha todo executed que existir em historyOrders, independentemente de estar em positionOrders
    # history_map = historyOrders.index_by { |h| h["ticketMaster"].to_s }
    # account.transactions.executed.each do |tx|
    #   if (params_for_tx = history_map[tx.ticket.to_s])
    #     transaction_closed(tx, params_for_tx, :copy_close)
    #   end
    # end
    
    return true
  end

  def transaction_closed(transaction, copy_params, kind)
    copySerializer = API::V3::CopySerializer.new(copy_params)

    if transaction and transaction.can_close?
      # transaction.order.messages << self
      
      transaction.trace.messages << message
      transaction.attributes = copySerializer.closed_attributes
      transaction.save
      transaction.loggings.create(content:copy_params, state: "CLOSED", changeset: transaction.try(:versions).try(:last).try(:changeset), parent: message.loggings.first, account: account, loggerable: message)
      transaction.update_mfe_mae(copySerializer) 
      
      if not transaction.error?
        if transaction.close 
          transaction.slaves.each do |transaction|
            transaction.loggings.create(content: "Automatically remove by close_orders: #{kind} - #{transaction.id}", state: "REMOVE", account: transaction.account, changeset: transaction.try(:versions).try(:last).try(:changeset), parent:message.loggings.first, loggerable: transaction.order.messages.last)
          end
        end
      else
        transaction.slaves.executed.map(&:remove)
      end
    end
  end

end