class	API::V3::CopyPresenter < API::V3::BasePresenter

	API_VERSION = "v3"

	attr_accessor :request, :message, :account

	def initialize(params, request, message, account)
		@params = params
		@request = request
		@message = message
		@account = account
	end

	def opening(jsons = nil, state = "COPY/OPEN")
		jsons  ||= positionOrders
	  if jsons.present?
	    logging = message.loggings.create(content: jsons, state: state, changeset: account.name, account: account, request_url: request.url, params: params, resourceable: account.store)		    
      traces = account.traces.copy.active
      if traces.present?
        changed = true
        jsons.each do |json|
          next if json.empty?

          state_meta = json["state_meta"]
          traces.active.not_deleted.each do |trace|
            @orders = trace.orders.where(content_id: json["ticketMaster"], account: account)
            if not @orders.present?
              begin
                message.traces << trace unless message.trace_ids.include?(trace.id)
                trace.create_order(json, account, message, json["symbol"], API_VERSION) 
              rescue ActiveRecord::RecordNotUnique
                message.loggings.create(content:"RecordNotUnique - Duplicate Slave Ticket #{json["ticketMaster"]} - Trace #{trace.id} #{trace.name} - Account #{account.name}", state: 'ERROR', resourceable: account, parent:message.loggings.last)
              end
            elsif @orders.present? 
              @orders.each do |order|
                order.transactions.each do |transaction|
                  serializer = API::V3::CopySerializer.new(json)
                  if transaction.stop_loss.try(:to_f) != serializer.stop_loss or transaction.take_profit.try(:to_f) != serializer.take_profit or transaction.profit.try(:to_f) != serializer.profit or transaction.price_open.try(:to_f) != serializer.price_open
                    message.orders << order unless message.order_ids.include?(order.id)
                    message.traces << trace unless message.trace_ids.include?(trace.id)
                    if transaction.update_modify_meta(serializer)
                      transaction.update_slaves(serializer)
                      transaction.update_mfe_mae(serializer)
                      version = transaction.try(:versions).try(:last)
                      transaction.loggings.create(content: serializer.obj, changeset: version.changeset, version: version, state: 'MODIFY', resourceable: order, account: account, parent: message.loggings.try(:first), request_url: message.try(:request_url), loggerable: message)
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
	    logging = message.loggings.create(content: pendingOrders, state: "COPY/PENDING", changeset: account.name, account: account, request_url: request.url, params: params)		    	    
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

	def closing
		message.loggings.create(content:message.content, state: "COPY/CLOSE", changeset: account.name, account: account, request_url: request.url, params: params)		    
	  if account
	    historyOrders.each do |json|
	      Transaction.executed.where(ticket: json["ticketMaster"], account: account).each do |transaction|          
	      	position = positionOrders.detect{|json| json["ticketMaster"] == transaction.ticket} 
	      	if position.blank?
	        	transaction_closed(transaction, json, :copy_close)
	        end
	      end
	    end
	  end
	    
	  if positionOrders.present?    
	    account.transactions.executed.each do |transaction|
	      ticket_id = transaction.ticket.to_s
	      unless positionOrders.detect{|json| json["ticketMaster"] == transaction.ticket} 
	        order_params = historyOrders.detect{|json| json["ticketMaster"] == ticket_id} || {}
	        transaction_closed(transaction, order_params, :copy_close) if order_params.present?
	      end
	    end        
	  end

	  # account.transactions.executed.each do |transaction|
	  #   ticket_id = transaction.ticket.to_s
	  #   order_params = historyOrders.detect{|json| json["ticketMaster"] == ticket_id} || {}
	  #   transaction_closed(transaction, order_params, :copy_close) if order_params.present?
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
	        transaction.slaves.each do |slave|
	          slave.loggings.create(content: "Automatically remove by close_orders: #{kind} - #{transaction.id}", state: "REMOVE", account: slave.account, changeset: slave.try(:versions).try(:last).try(:changeset), parent:message.loggings.first, loggerable: slave.order.messages.last)
	        end
	      end
	    else
	      transaction.slaves.executed.map(&:remove)
	    end
	  end
	end


	def conciliate
	  transactions = account.masters.not_executed
	  copy_profit = transactions.map(&:profit).compact.sum
	  if(json["HistoryOrdersProfit"].to_f != copy_profit.to_f and account.api_send_orders_history == false)
	    account.update(api_send_orders_history: true)
	  end

	  if(json["HistoryOrdersCount"].to_i == historyOrders.count)
	    if historyOrders.map { |h| h["profit"] }.sum.to_f != copy_profit.to_f
	      transactions.update_all(profit: 0)
	      account.loggings.create(state: "conciliated_account_zero", content: json, request_url: request.url)

	      transactions.each do |t| 
	        delete = false
	        historyOrders.each do |json| 
	          delete = json["ticketMaster"] == t.ticket
	          break if delete
	        end
	        t.update(profit: 0) unless delete
	      end
	    end
	    account.update(api_send_orders_history: false)
	  end

	  historyOrders.each do |json|
	    change = false
	    symbol = json["symbol"]
	    transaction = Transaction.find_by(symbol: symbol, ticket: json["positionID"], account: account)
	    if transaction
	      if json["profit"].to_f != transaction.profit
	        transaction.profit = json["profit"].to_f
	        transaction.save
	        # if transaction.state == "pending" || transaction.state == "executed"
	        #   transaction.close
	        # end
	        change = true
	      end
	    else
	      order = Order.find_by(symbol: symbol, content_id: json["ticketMaster"])
	      ticket_master = 0
	      if order
	        trace = order.trace
	        comment = json["ticketMaster"]
	      else
	        comment = "conciliate_order"
	        trace = Trace.create_with(name: "manual_orders", name_id: -1, store: account.store, kind: 2, contract_volume_max: 1, customer_plans: [account.store.customer_plans.first])
	                    .find_or_create_by(name: "manual_orders", name_id: -1)
	        order = Order.create(symbol: symbol, content: json, content_id: ticket_master, account: account, state: 'conciliated', store: account.store, trace: trace)
	      end
	      serializer = API::V3::CopySerializer.new(json)
	      attributes = serializer.trace_attributes(symbol, account, nil, trace)
	                     .merge(state: "closed", profit: json["profit"], comment: comment, open_at: json["openAt"], closed_at: json["closeAt"], price_open: json['priceOpen'])
	      transaction = order.transactions.create(attributes)
	      change = true
	    end
	    if change
	      transaction.loggings.create(state: "conciliated", content: json, resourceable: transaction, changeset: transaction.versions.try(:last).try(:changeset), version: transaction.versions.try(:last), parent: transaction.loggings.try(:first), request_url: request.url, account: account)
	    end
	  end
	end

end