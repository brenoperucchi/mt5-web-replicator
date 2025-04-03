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

  def closing
    message.loggings.create(content:message.content, state: "COPY/CLOSE", changeset: account.name, account: account, request_url: message.request_url, params: params)        
    if account
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
      account.transactions.executed.each do |transaction|
        unless positionOrders.detect{|json| json["ticketMaster"] == transaction.ticket} 
          order_params = historyOrders.detect{|json| json["ticketMaster"] == transaction.ticket} || {}
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
          transaction.slaves.each do |transaction|
            transaction.loggings.create(content: "Automatically remove by close_orders: #{kind} - #{transaction.id}", state: "REMOVE", account: transaction.account, changeset: transaction.try(:versions).try(:last).try(:changeset), parent:message.loggings.first, loggerable: transaction.order.messages.last)
          end
        end
      else
        transaction.slaves.executed.map(&:remove)
      end
    end
  end

  def conciliate
    conciliate_inittial
    if account.api_send_orders_history
      message.loggings.create(content: json, state: "COPY/CONCILIATE", params: params, request_url: message.request_url, account: account, resourceable:account)
      trace_ajust_profit
      account.update(api_send_orders_history: false)
    end
  end


  private

  def conciliate_inittial
    historyOrders.group_by{|h| [h["positionID"],h["symbol"]]}.each do |(positionID, symbol), jsons|
      conciliate_position(positionID, symbol, jsons)
    end
  end

  def trace_ajust_profit
    trace = find_or_create_trace
    profit = calculate_slaves_by(trace, :profit)
    fee    = calculate_slaves_by(trace, :fee)
    time   = @account.store.created_at.strftime("%Y.%m.%d %T")
    
    json_last = { "ticketMaster" => -1, "ticketSlave" => -1, "ticketDeal" => -1, "positionID" => -1, "type" => 0, "entry" => 0, "traceID" => 0,
             "slaveID" => 0, "magicNumber" => 0, "transactionID" => 0, "slipPage" => 0, "symbolDigits" => 0, "timeZone" => 0, "profit" => profit,
             "priceOpen" => 0, "priceClose" => 0, "priceRequest" => 0, "stopLoss" => 0, "takeProfit" => 0, "volume" => 0, "commission" => 0.00,
             "fee" => fee, "swap" => 0.00, "mae" => 0.00, "mfe" => 0.00, "state" => "closed", "metaAction" => "", "metaState" => "", "metaMessage" => "",
             "symbol" => "conciliated", "comment" => "-#{trace.id}#{@account.id}--#{-1}", "openAt" => time, "closeAt" => time, "timeGMT" => time, "timeTrader" => time
           }

    profit_conciliated = -1 * (profit - json["HistoryOrdersProfit"].to_f)&.round(2) 
    fee_conciliated    = -1 * (fee    - json["HistoryOrdersFee"].to_f)&.round(2) 
    volume             = json_last["volume"].to_f

    # order = find_or_create_order(json_last)
        
    order = find_or_create_order(json_last, trace)
    transaction = account.transactions.conciliated.find_by(symbol: 'conciliated', ticket: -1, account: account)
    if transaction.present?
      if profit_conciliated !=0 || fee_conciliated != 0
        serializer = API::V3::CopySerializer.new(json_last)
        update_existing_transaction(transaction, profit_conciliated, fee_conciliated, volume, serializer, order)
      end
    else
      create_new_transaction(json_last, profit_conciliated, fee_conciliated, volume)
    end
  end

  def conciliate_position(positionID, symbol, jsons)
    json_last    = jsons.last
    profit       = jsons.sum {|j| j["profit"].to_f }&.round(2)
    fee          = jsons.sum {|j| j["fee"].to_f }&.round(2) 
    commission   = jsons.sum {|j| j["commission"].to_f }&.round(2) 
    swap         = jsons.sum {|j| j["swap"].to_f }&.round(2) 
    volume       = jsons.sum {|j| j["volume"].to_f }&.round(2) 
    fee          = fee + commission + swap
    transactions = Transaction.where(symbol: symbol, ticket: positionID, account: account)
    
    if transactions.present?
      transactions.each do |transaction|    
        serializer = API::V3::CopySerializer.new(json_last)
        if transaction && !transaction.conciliated?
          order = find_or_create_order(json_last, transaction.trace)
          update_existing_transaction(transaction, profit, fee, volume, serializer, order)
        end
      end
    else
      create_new_transaction(json_last, profit, fee, volume)
    end
  end

  def update_existing_transaction(transaction, profit, fee, volume, serializer, order)
    trace = transaction.trace
    trace ||= order.trace
    trace ||= find_or_create_trace

  
    # if profit != transaction.try(:profit).to_f || transaction.lot.to_f != volume
    if profit != transaction.try(:profit).to_f || transaction.lot.to_f != volume || transaction.fee.to_f != fee
      transaction.profit = profit.to_f
      transaction.fee    = fee.to_f
      transaction.lot    = volume.to_f
      transaction.state  = 'closed'
      transaction.trace  = trace
      transaction.closed_at      = serializer.closed_at if transaction.closed_at.nil?
      transaction.conciliated_at = Time.current
      
      if transaction.save
        order.transactions << transaction unless order.transactions.exists?(transaction.id)
        account.orders << order unless account.orders.exists?(order.id) 
        message.orders << order unless message.orders.exists?(order.id) 
        log_conciliation(transaction, serializer.obj)
      end
    end
    return true
  end

  def create_new_transaction(json_last, profit, fee, volume)
    trace = find_or_create_trace
    order = find_or_create_order(json_last, trace)
    symbol = json_last["symbol"]
    serializer = API::V3::CopySerializer.new(json_last)

    # Explicitly ensure the correct account instance is passed
    attributes = serializer.trace_attributes(symbol, nil, nil, order.trace)
                 .merge(
                   state: "closed",
                   profit: profit,
                   lot: volume,
                   fee: fee,
                   account_id: account.id,
                   price_open: json_last['priceOpen'],
                   open_at: json_last["openAt"],
                   closed_at: json_last["closeAt"],
                   conciliated_at: Time.current,
                   comment: json_last["comment"] || "conciliate_order",
                 )

    transaction = order.transactions.new(attributes)
    if transaction.save
      order.transactions << transaction unless order.transactions.exists?(transaction.id)
      account.orders << order unless account.orders.exists?(order.id) 
      message.orders << order unless message.orders.exists?(order.id) 
      log_conciliation(transaction, json_last)
    end
    return true
  end

  def find_or_create_trace
    trace_name = "conciliated##{@account.name}"
    trace_name_id = "-1#{@account.id}".to_i
    trace = Trace.joins(:store_traces).where(name: trace_name, name_id: trace_name_id).where(store_traces: { store_id: account.store.id }).take
    trace ||= Trace.new(
         kind: 2,
         contract_volume_max: 1,
         name: trace_name,
         name_id: trace_name_id,
         stores: [account.store],
         customer_plans: [account.store.customer_plans.first]
       )
    if trace.save
      trace.accounts << account unless trace.accounts.exists?(account.id)
      trace.stores << account.store unless trace.stores.exists?(account.store.id)
    end    
    trace
  end
  
  def find_or_create_order(json_last, trace = nil)
    symbol = json_last["symbol"]
    content_id = json_last["positionID"]
    
    trace ||= find_or_create_trace
    order = Order.find_by(symbol: json_last['symbol'], content_id: content_id, account: @account)
    order ||= Order.create(
      symbol: symbol,
      content: json_last,
      content_id: content_id,
      account: account,
      state: 'closed',
      store: account.store,
      trace: trace,
      message: message,
      conciliated_at: Time.current
    )
  end

  def log_conciliation(transaction, content)
    begin
      transaction.loggings.create(
        state: "conciliated",
        content: content,
        changeset: transaction.versions.try(:last).try(:changeset),
        version: transaction.versions.try(:last),
        parent: transaction.loggings.try(:first),
        request_url: message.request_url,
        account_id: account.id
      )
    rescue ActiveRecord::RecordNotSaved => e
      transaction.loggings.create(
        state: "conciliated_error",
        content: e.message,
        changeset: transaction.versions.try(:last).try(:changeset),
        version: transaction.versions.try(:last)
      )
    end
  end

  def calculate_slaves_by(trace, kind = :profit)
    profit = 0
    fee    = 0
    @account.traces.each do |trace|
      profit += trace.transactions.sum(:profit)&.to_f
      fee    += trace.transactions.sum(:fee)&.to_f
    end
  
    if kind == :profit
      return profit.round(2)
    else
      return fee.round(2)
    end
  end

end