class API::V3::SlaveConciliatePresenter < API::V3::BasePresenter

  API_VERSION = "v3"

  attr_accessor :params, :request, :response, :account, :message

  def initialize(params, message, account)
    @params      = params
    @message     = message
    @account     = account
  end

  def conciliate
    conciliate_by_order
    if json['ApiSendOrdersHistory'].to_b# && account.api_send_orders_history
      ## TODO MELHORAR NUMA TRANSACAO DENTRO conciliate_by_total
      message.execute if message.save
      message.loggings.create(content: json, state: "SLAVE/CONCILIATE", params: params, request_url: message.request_url, account: account, resourceable:account)
      conciliate_by_month
      conciliate_by_total
      ## TODO MELHORAR
      account.update(api_send_orders_history: false)
    end
  end

  private

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
      slave = account.slaves.find_by(symbol: symbol_name, ticket_slave: -1, account: account)
      
      profit_orders = orders.sum { |o| o["profit"].to_f }.round(2)
      fee_orders    = orders.sum { |o| o["fee"].to_f + o["commission"].to_f + o["swap"].to_f }.round(2)

      volume = orders.sum { |o| o["volume"].to_f }.round(2)
      # Convertendo para DateTime com timezone -0300
      date_month = DateTime.strptime("#{year_month}01 -0300", "%Y%m%d %z")
      # Define o range usando o timezone correto
      range = (date_month.beginning_of_month...date_month.next_month.beginning_of_month)
      
      account_profit = calculate_by_account_total(:profit, range)
      account_fee    = calculate_by_account_total(:fee, range)
      
      profit = (profit_orders - account_profit)&.round(2)
      fee    = (fee_orders - account_fee)&.round(2)

      orders_total = profit_orders + fee
      account_total = account_profit + account_fee
      
      if profit.zero? && fee.zero? 
        next
      else
        profit = (profit_orders - account_profit + slave&.profit.to_f)&.round(2)
        fee    = (fee_orders - account_fee + slave&.fee.to_f)&.round(2)
      end
      
      json_last = orders.last.dup
      # Monta um json_last representativo do mês
      json_last["profit"] = profit
      json_last["fee"] = fee
      json_last["volume"] = volume
      json_last["symbol"] = symbol_name
      json_last["positionID"] = -1
      json_last["ticketSlave"] = -1
      json_last["ticketMaster"] = -1
      json_last["comment"] = "conciliated"
      json_last["openAt"] = date_month.end_of_month.strftime("%Y.%m.%d %T")
      json_last["closeAt"] = date_month.end_of_month.strftime("%Y.%m.%d %T")
      
      # Busca ou cria a transação de ajuste do mês
      order = find_or_create_order(json_last, trace)
      order.state = "conciliated"
      order.save

      next if fee.zero? && profit.zero? && slave&.profit.to_f == profit && slave&.fee.to_f == fee && slave&.lot.to_f == volume 
      
      if slave.present?
        # serializer = API::V3::SlaveSerializer.new(json_last)
        update_existing_slave(slave, json_last, order)
      else
        
        create_new_slave(json_last, trace, order)
      end
    end
  end

  def conciliate_by_order
    orders = historyOrders.group_by{|h| [h["positionID"],h["symbol"]]}
    results =[]
    orders.each do |(positionID, symbol), jsons|
      results << conciliate_position(positionID, symbol, jsons)
    end

    if results.flatten.include?(true) 
      message.conciliate
      message.loggings.create(content: json, state: "SLAVE/CONCILIATE", params: params, request_url: message.request_url, account: account, resourceable:account)
    end
    # Rails.logger.info "COUNT: #{count}"
    # Rails.logger.info "Conciliate by month: #{orders.count}"
  end

  def conciliate_position(positionID, symbol, jsons)
    json_last             = jsons.last
    json_last["profit"]   = jsons.sum { |j| j["profit"].to_f }&.round(2)
    json_last["fee"]      = jsons.sum { |j| j["fee"].to_f + j["commission"].to_f + j["swap"].to_f }.round(2)
    json_last["volume"]   = jsons.sum { |j| j["volume"].to_f }&.round(2) 

    
    trace_id  = normalize_comment(json_last['comment'])&.first&.to_i&.abs
    trace     = Trace.find_by(id: trace_id) || find_or_create_trace
    slaves    = TransactionSlave.where(symbol: symbol, ticket_slave: positionID, account: account)
    results   = []

    if slaves.present?
      slaves.each do |slave|    
        serializer = API::V3::SlaveSerializer.new(json_last)
        if slave && !slave.conciliated?
          order = slave.order || find_or_create_order(json_last, trace)
          results << update_existing_slave(slave, json_last, order)
        end
      end
    else
      order = find_or_create_order(json_last, trace)
      results << create_new_slave(json_last, trace, order)
    end
    return results
  end

  def conciliate_by_total
    trace  = find_or_create_trace
    profit = calculate_by_account(:profit)
    fee    = calculate_by_account(:fee)
    time   = @account.store.created_at.strftime("%Y.%m.%d %T")
    
    json_last = { "ticketMaster" => -1, "ticketSlave" => -1, "ticketDeal" => -1, "positionID" => -1, "type" => 0, "entry" => 0, "traceID" => 0,
            "slaveID" => 0, "magicNumber" => 0, "transactionID" => 0, "slipPage" => 0, "symbolDigits" => 0, "timeZone" => 0, "profit" => 0,
            "priceOpen" => 0, "priceClose" => 0, "priceRequest" => 0, "stopLoss" => 0, "takeProfit" => 0, "volume" => 0, "commission" => 0.00,
            "fee" => 0, "swap" => 0.00, "mae" => 0.00, "mfe" => 0.00, "state" => "closed", "metaAction" => "", "metaState" => "", "metaMessage" => "",
            "symbol" => "conciliated", "comment" => "conciliated", "openAt" => time, "closeAt" => time, "timeGMT" => time, "timeTrader" => time
          }

    json_last["profit"] = (json['HistoryOrdersProfit'].to_f - profit)&.round(2)
    json_last["fee"]    = (json['HistoryOrdersFee'].to_f - fee)&.round(2)

    return if json_last["profit"]&.zero? && json_last["fee"]&.zero?

    order = find_or_create_order(json_last, trace)
    slave = trace.slaves.find_by(symbol: 'conciliated', ticket_slave: -1, account: account)
    if slave.present?
      # serializer = API::V3::SlaveSerializer.new(json_last)
      update_existing_slave(slave, json_last, order)
    else
      create_new_slave(json_last, trace, order)
    end
  end

  def update_existing_slave(slave, json_last, order)
    trace   = order.trace
    trace ||= slave.trace
    trace ||= find_or_create_trace

    # if slave.profit.to_f != serializer.profit.to_f || slave.lot.to_f != 0 || slave.fee.to_f != 0
    if slave.profit.to_f != json_last["profit"].to_f || slave.lot.to_f != json_last["volume"].to_f || slave.fee.to_f != json_last["fee"].to_f
      serializer = API::V3::SlaveSerializer.new(json_last)
      slave.profit = json_last["profit"]&.round(2)
      slave.fee = json_last["fee"]&.round(2)
      slave.lot = json_last["volume"].to_f
      slave.state = 'closed'
      slave.trace = trace
      slave.closed_at = serializer.closed_at# if slave.closed_at.nil?
      slave.conciliated_at = Time.current

      if slave.save
        order.update(state: 'closed', conciliated_at: Time.current)
        order.slaves << slave unless order.slaves.exists?(slave.id)
        account.orders << order unless account.orders.exists?(order.id) 
        message.orders << order unless message.orders.exists?(order.id) 
        log_conciliation(slave, json_last) 
        return true       
      else 
        content = "Error on UPDATE Slave Conciliate: Account #{account.name} - Errors: #{slave.errors.full_messages.join(",")} - Attributes: #{json_last}"
        log_conciliation(slave, content, "ERROR")
      end
    end
    return false
  end

  def create_new_slave(json_last, trace, order)
    transaction = find_or_create_transaction(json_last["symbol"], json_last["positionID"], json_last, trace) unless json_last["symbol"] == 'conciliated'
    serializer = API::V3::SlaveSerializer.new(json_last)
    attributes = serializer.trace_attributes(json_last["symbol"], account, nil, trace, account.store)
                .merge(
                  state: 'closed',
                  profit: json_last["profit"]&.to_f&.round(2),
                  lot: json_last["volume"]&.to_f&.round(2),
                  fee: json_last["fee"]&.to_f&.round(2),
                  price_open: serializer.price_open,
                  open_at: serializer.open_at,
                  closed_at: serializer.closed_at,
                  conciliated_at: Time.current,
                  comment: json_last["comment"] || "conciliate_order",
                  master: transaction,
                ).compact
    slave = order.slaves.new(attributes)
    if slave.save
      order.slaves << slave unless order.slaves.exists?(slave.id)
      account.orders << order unless account.orders.exists?(order.id) 
      message.orders << order unless message.orders.exists?(order.id) 
      log_conciliation(slave, json_last)
      return true
    else 
      content = "Error on CREATE Slave Conciliate: Account #{account.name} - Errors: #{slave.errors.full_messages.join(",")} - Attributes: #{json_last}"
      log_conciliation(slave, content, "ERROR")
    end
    return false
  end

  def normalize_comment(comment)
    return nil if comment.nil? || comment.strip.empty?

    if comment.include?('--')
      comment.split('--')
    elsif comment.include?('-')
      comment.split('-')
    else
      # Check if it's purely a number
      if comment.match?(/\A\d+\z/)
        [comment]
      else
        nil
      end
    end
  end

  def find_or_create_transaction(symbol, positionID, json_last, trace)
    ticket = normalize_comment(json_last["comment"])&.last
    transaction = Transaction.find_by(trace_id: trace.id, ticket: ticket)   
  end

  def find_or_create_order(json_last, trace)
    if json_last['symbol'] == 'conciliated'
      content_id = -1
    else
      content_id = normalize_comment(json_last['comment'])&.last&.to_i&.abs || json_last["positionID"]
    end

    Order.find_by(symbol: json_last['symbol'], content_id: content_id, account: @account) || create_new_order(json_last['symbol'], content_id, json_last, trace)
  end

  def find_or_create_trace
    trace_name = "conciliated##{@account.name}"
    trace_name_id = "-1#{@account.id}".to_i
    trace = Trace.joins(:store_traces).where(name: trace_name, name_id: trace_name_id).where(store_traces: { store_id: account.store.id }).take
    if trace.nil?
      trace = Trace.new(
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
    end
    trace
  end

  def create_new_order(symbol, content_id, json_last, trace)
    order = Order.new(
        symbol: symbol,
        content: json_last,
        content_id: content_id,
        account: @account,
        state: 'closed',
        store: account.store,
        trace: trace,
        message: message,
        conciliated_at: Time.current
      )
    order.save
    order
  end

  def log_conciliation(slave, content, state = "conciliated")
    attributes = {
      state: state,
      content: content,
      resourceable: slave,
      changeset: slave.versions.try(:last).try(:changeset),
      version: slave.versions.try(:last),
      parent: slave.loggings.try(:first),
      request_url: message.request_url,
      account: account
    }.compact
    logging = Logging.new(attributes)
    logging.save
  end

  # Exemplo de refatoração para calculate_by_account_total (Slave)
  def calculate_by_account_total(kind = :profit, range = nil)
    query = account.slaves
    query = query.where(closed_at: range) if range.present?

    if kind == :profit
      query.sum(:profit).round(2) # Usar sum direto do DB
    else
      # Assumindo que 'fee' é uma coluna numérica
      query.sum(:fee).round(2) # Usar sum direto do DB 
    end
  end

  # Exemplo de refatoração para calculate_by_account (Slave)
  def calculate_by_account(kind = :profit, range = nil)
    # Ajustar a query conforme a necessidade (excluindo 'conciliated')
    query = account.slaves.where.not(symbol: "conciliated") 
    query = query.where(closed_at: range) if range.present?
    
    if kind == :profit
      query.sum(:profit).round(2)
    else
      query.sum(:fee).round(2)
    end
  end
end