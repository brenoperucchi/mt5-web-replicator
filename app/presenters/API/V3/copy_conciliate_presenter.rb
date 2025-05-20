class API::V3::CopyConciliatePresenter < API::V3::BasePresenter

  API_VERSION = "v3"

  attr_accessor :message, :account

  def initialize(params, message, account)
    @params = params
    @message = message
    @account = account
  end

  def conciliate
    conciliate_by_order
    if json['ApiSendOrdersHistory'].to_b #&& account.api_send_orders_history
      message.loggings.create(content: json, state: "COPY/CONCILIATE", params: params, request_url: message.request_url, account: account, resourceable:account)
      conciliate_by_month
      conciliate_by_total
      account.update(api_send_orders_history: false)
    end
  end

  private

  def conciliate_by_order
    historyOrders.group_by{|h| [h["positionID"],h["symbol"]]}.each do |(positionID, symbol), jsons|
      conciliate_position(positionID, symbol, jsons)
    end
  end

  # Conciliação mensal baseada nas ordens históricas
  def conciliate_by_month
    # Agrupa as ordens por ano-mês usando a data de fechamento (closeAt) ou abertura (openAt)
    grouped = historyOrders.group_by do |order|
      date_str = order["closeAt"] || order["openAt"]
      date = if date_str
        begin
          Date.parse(date_str.to_s)
        rescue
          nil
        end
      else
        nil
      end
      date ? date.strftime("%Y%m") : "unknown"
    end

    grouped.each do |year_month, orders|
      next if year_month == "unknown"
      
      trace = find_or_create_trace
      symbol_name = "#{trace.id}-#{year_month}"
      transaction = account.transactions.find_by(symbol: symbol_name, ticket: -1, account: account)
      
      profit_orders = orders.sum { |o| o["profit"].to_f }.round(2)
      fee_orders    = orders.sum { |o| o["fee"].to_f + o["commission"].to_f + o["swap"].to_f }.round(2)
      volume = orders.sum { |o| o["volume"].to_f }.round(2)
      # date_month = Date.strptime(year_month, "%Y%m")
      date_month = DateTime.strptime("#{year_month}01 -0300", "%Y%m%d %z")
      range = (date_month.beginning_of_month...date_month.next_month.beginning_of_month)

      account_profit = calculate_by_account_total(:profit, range)
      account_fee    = calculate_by_account_total(:fee, range)
      
      profit = (profit_orders - account_profit)&.round(2)
      fee    = (fee_orders - account_fee)&.round(2)

      orders_total = profit_orders + fee
      account_total = account_profit + account_fee

      # binding.pry if year_month == "202504"

      if profit.zero? && fee.zero? 
        next
      else
        profit = (profit_orders - account_profit + transaction&.profit.to_f)&.round(2)
        fee    = (fee_orders - account_fee + transaction&.fee.to_f)&.round(2)
      end
      
      # Monta um json_last representativo do mês
      json_last = orders.last.dup
      json_last["profit"] = profit
      json_last["fee"] = fee
      json_last["volume"] = volume
      json_last["symbol"] = symbol_name
      json_last["ticketMaster"] = -1
      json_last["positionID"] = -1
      json_last["comment"] = "conciliated"
      json_last["openAt"] = date_month.end_of_month.strftime("%Y.%m.%d %T")
      json_last["closeAt"] = date_month.end_of_month.strftime("%Y.%m.%d %T")
      
      # Busca ou cria a transação de ajuste do mês
      order = find_or_create_order(json_last, trace)
      order.state = "conciliated"
      order.save
      
      next if fee.zero? && profit.zero? && transaction&.profit.to_f == profit && transaction&.fee.to_f == fee && transaction&.lot.to_f == volume 
      if transaction.present?
        # serializer = API::V3::CopySerializer.new(json_last)
        update_existing_transaction(transaction, json_last, order)
      else
        create_new_transaction(json_last, trace, order)
      end
    end
  end

  def conciliate_by_total
    trace = find_or_create_trace
    profit = calculate_by_account(:profit)
    fee    = calculate_by_account(:fee)
    # time   = DateTime.now.strftime("%Y.%m.%d %T")
    time   = @account.store.created_at.strftime("%Y.%m.%d %T")
    current_month = DateTime.now.strftime("%Y-%m")
    symbol_name = "#{trace.id}-#{current_month}"
    
    json_last = { "ticketMaster" => -1, "ticketSlave" => -1, "ticketDeal" => -1, "positionID" => -1, "type" => 0, "entry" => 0, "traceID" => 0,
             "slaveID" => 0, "magicNumber" => 0, "transactionID" => 0, "slipPage" => 0, "symbolDigits" => 0, "timeZone" => 0, "profit" => profit,
             "priceOpen" => 0, "priceClose" => 0, "priceRequest" => 0, "stopLoss" => 0, "takeProfit" => 0, "volume" => 0, "commission" => 0.00,
             "fee" => fee, "swap" => 0.00, "mae" => 0.00, "mfe" => 0.00, "state" => "closed", "metaAction" => "", "metaState" => "", "metaMessage" => "",
             "symbol" => "conciliated", "comment" => "-#{trace.id}#{@account.id}--#{-1}", "openAt" => time, "closeAt" => time, "timeGMT" => time, "timeTrader" => time
           }
    
    conciliated_profit  = Transaction.where(symbol: 'conciliated', ticket: -1, account: account).sum(&:profit).to_f
    conciliated_fee  = Transaction.where(symbol: 'conciliated', ticket: -1, account: account).sum(&:fee).to_f

    json_last["profit"] = (json['HistoryOrdersProfit'].to_f - profit)&.round(2)
    json_last["fee"]    = (json['HistoryOrdersFee'].to_f - fee)&.round(2)
    volume              = json_last["volume"].to_f
    
    profit_account =  (profit + fee).round(2)
    profit_orders = (json['HistoryOrdersProfit'].to_f + json['HistoryOrdersFee'].to_f).round(2)
    
    total_amount_json = json_last["profit"].to_f + json_last["fee"].to_f
    total_amount = profit_orders - profit_account + conciliated_profit + conciliated_fee
    
    order = find_or_create_order(json_last, trace)

    transaction = account.transactions.find_by(symbol: "conciliated", ticket: -1, account: account)
    if transaction.present?
      if json_last["profit"] != 0 || json_last["fee"] != 0
        # serializer = API::V3::CopySerializer.new(json_last)
        update_existing_transaction(transaction, json_last, order)
      end
    else
      transaction = create_new_transaction(json_last, trace, order)
    end


    if transaction.profit != json_last["profit"] || transaction.fee != json_last["fee"]
      Rails.logger.error("[ERROR] Transação não atualizada: #{transaction.id}")
      SystemAlert.create(
        message: "Transação não atualizada: #{transaction.id}",
        serverity: "info",
        source: "transaction",
        source_id: transaction.id,
        alertable: transaction,
        details: {
          account_id: account.id,
          trace_id: transaction.trace_id,
          volume: transaction.lot,
          profit: json_last["profit"],
          fee: json_last["fee"],
          historyOrdersProfit: transaction.historyOrdersProfit,
          historyOrdersFee: transaction.historyOrdersFee
        }
      )
    end

  end

  def conciliate_position(positionID, symbol, jsons)
    json_last           = jsons.last
    json_last["profit"] = jsons.sum { |j| j["profit"].to_f }&.round(2)
    json_last["volume"] = jsons.sum { |j| j["volume"].to_f }&.round(2) 
    json_last["fee"]    = jsons.sum { |j| j["fee"].to_f + j["commission"].to_f + j["swap"].to_f }.round(2)
    trace               = find_or_create_trace
    transactions        = Transaction.where(symbol: symbol, ticket: positionID, account: account)
    
    if transactions.present?
      transactions.each do |transaction|    
        serializer = API::V3::CopySerializer.new(json_last)
        order = find_or_create_order(json_last, transaction.trace)
        if transaction && !transaction.conciliated?
          update_existing_transaction(transaction, json_last, order)
        end
      end
    else
      order = find_or_create_order(json_last, trace)
      create_new_transaction(json_last, trace, order)
    end
  end

  def update_existing_transaction(transaction, json_last, order)
    trace   = order.trace
    trace ||= transaction.trace
    trace ||= find_or_create_trace

  
    # if profit != transaction.try(:profit).to_f || transaction.lot.to_f != volume
    # if json_last.profit.to_f != transaction.try(:profit).to_f || transaction.lot.to_f != json_last["volume"].to_f || transaction.fee.to_f != json_last["fee"].to_f
    if json_last["profit"].to_f != transaction.try(:profit).to_f || transaction.lot.to_f != json_last["volume"].to_f || transaction.fee.to_f != json_last["fee"].to_f
      transaction.profit = json_last["profit"].to_f
      transaction.fee    = json_last["fee"].to_f
      transaction.lot    = json_last["volume"].to_f
      transaction.state  = 'closed'
      transaction.trace  = trace
      transaction.closed_at = json_last["closeAt"] if transaction.closed_at.nil?
      transaction.conciliated_at = Time.current
      
      if transaction.save
        order.transactions << transaction unless order.transactions.exists?(transaction.id)
        account.orders << order unless account.orders.exists?(order.id) 
        message.orders << order unless message.orders.exists?(order.id) 
        log_conciliation(transaction, json_last)
      end
    end
    return true
  end

  def create_new_transaction(json_last, trace, order = nil)
    trace ||= find_or_create_trace
    order ||= find_or_create_order(json_last, trace)
    symbol = json_last["symbol"]
    serializer = API::V3::CopySerializer.new(json_last)

    # Explicitly ensure the correct account instance is passed
    attributes = serializer.trace_attributes(symbol, nil, nil, order.trace)
                 .merge(
                   state: "closed",
                   profit: json_last["profit"],
                   lot: json_last["volume"],
                   fee: json_last["fee"],
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
    transaction
  end

  def find_or_create_trace
    trace_name = "conciliated##{@account.name}"
    trace_name_id = "-1#{@account.id}".to_i

    # Add validation for required data
    unless @account && @account.name && @account.store
      Rails.logger.error("[ERROR] Invalid account data for trace creation: " + 
        {account_id: @account&.id, account_name: @account&.name, store_id: @account&.store&.id}.to_json)
      return nil
    end

    trace = Trace.joins(:store_traces)
              .where(name: trace_name, name_id: trace_name_id)
              .where(store_traces: { store_id: account.store.id })
              .take

    if trace.nil?
      # Check for customer plan before creating trace
      if account.store.customer_plans.empty?
        Rails.logger.error("[ERROR] No customer plans found for account #{account.id} (store #{account.store.id})")
        return nil
      end

      # Log attempt to create new trace
      Rails.logger.info("[DEBUG] Creating new trace: #{trace_name}")

      begin
        customer_plan = account.store.customer_plans.first

        # Add validation for customer plan
        if customer_plan.nil? || !customer_plan.valid?
          Rails.logger.error("[ERROR] Customer plan is invalid for account #{account.id}: " +
            {customer_plan_id: customer_plan&.id, errors: customer_plan&.errors&.full_messages}.to_json)
          return nil
        end

        trace = Trace.new(
          kind: 2,
          contract_volume_max: 1,
          name: trace_name,
          name_id: trace_name_id,
          stores: [account.store],
          customer_plans: [customer_plan]
        )

        unless trace.save
          Rails.logger.error("[ERROR] Failed to save trace: #{trace.errors.full_messages.join(', ')}")
          Rails.logger.error("[ERROR] Customer plan details: ID=#{customer_plan.id}, Valid=#{customer_plan.valid?}, Errors=#{customer_plan.errors.full_messages.join(', ')}")
          return nil
        end

        trace.accounts << account unless trace.accounts.exists?(account.id)
        trace.stores << account.store unless trace.stores.exists?(account.store.id)
      rescue => e
        Rails.logger.error("[ERROR] Exception creating trace: #{e.message}")
        Rails.logger.error("[ERROR] Backtrace: #{e.backtrace.first(5).join('\n')}")
        return nil
      end
    end

    trace
  end

  def find_or_create_order(json_last, trace = nil)
    symbol = json_last["symbol"]
    content_id = json_last["positionID"]
    
    # Log input parameters
    debug_info = {
      method: "find_or_create_order",
      symbol: symbol,
      content_id: content_id,
      account_id: account&.id,
      trace_param: trace&.id,
      json_last_sample: json_last.slice("symbol", "positionID", "profit", "fee").to_json
    }
    
    # Ensure we have a valid trace
    if trace.nil?
      Rails.logger.info("[DEBUG] trace is nil, attempting to find_or_create_trace: #{debug_info.to_json}")
      trace = find_or_create_trace
      debug_info[:trace_after_find_or_create] = trace&.id
      
      # If trace is still nil after find_or_create_trace, this is the root cause
      if trace.nil?
        error_message = "Failed to create or find trace for order"
        Rails.logger.error("[ERROR] #{error_message}: #{debug_info.to_json}")
        
        # Create an error log record for later investigation
        if defined?(Logging)
          Logging.create(
            content: debug_info,
            state: "TRACE_CREATION_ERROR",
            params: @params,
            request_url: message&.request_url,
            account: account,
            resourceable: account
          )
        end
        
        # Use RuntimeError instead of ActiveRecord::RecordInvalid to avoid errors method call
        raise RuntimeError.new("Trace cannot be created when creating Order (account_id: #{account&.id}, symbol: #{symbol})")
      end
    end
    
    # Now find or create the order with proper trace validation
    order = Order.find_by(symbol: json_last['symbol'], content_id: content_id, account: @account)
    
    unless order
      begin
        order = Order.create!(
          symbol: symbol,
          content: json_last,
          content_id: content_id,
          account: account,
          state: 'closed',
          store: account.store,
          trace: trace,  # This should now always have a value
          message: message,
          conciliated_at: Time.current
        )
        Rails.logger.info("[DEBUG] Successfully created Order: #{order.id}")
      rescue => e
        error_info = debug_info.merge(error: e.message, backtrace: e.backtrace.first(5))
        Rails.logger.error("[ERROR] Order creation failed: #{error_info.to_json}")
        
        # Create an error log record
        if message&.respond_to?(:loggings)
          message.loggings.create(
            content: error_info,
            state: "ORDER_CREATION_ERROR",
            params: @params,
            request_url: message.request_url,
            account: account,
            resourceable: account
          )
        end
        
        raise # Re-raise the exception
      end
    end
    
    order
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

  def calculate_by_account(kind = :profit, range = nil)
    profit = 0
    fee    = 0
    query = account.transactions.where.not(symbol: "conciliated")
    query = query.where(closed_at: range) if range.present?
    
    if kind == :profit
      query.sum{|s| s.profit.to_f}&.round(2)
    else
      query.sum{|s| s.fee.to_f}&.round(2)
    end  
  end

  def calculate_by_account_total(kind = :profit, range = nil)
    transactions = []
    transactions += range.present? ? account&.transactions&.where(closed_at: range) : account&.transactions
  
    if kind == :profit
      return transactions&.sum{|s| s.profit.to_f}&.round(2)
    else
      return transactions&.sum{|s| s.fee.to_f}&.round(2)
    end
  end
  

end