class API::V3::SlavePresenter < API::V3::BasePresenter

  API_VERSION = "v3"

  attr_accessor :params, :request, :response, :account, :message

  def initialize(params, message, account)
    @params      = params
    @message     = message
    @account     = account
  end

  def slaves
    @response = account&.slaves&.opened&.where&.not(transaction_id: nil).where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 31.days))
                                                                        .collect { |t| t.api_request_attributes }.join('/')
  end


  def execute_status
    map          = String.new
    date_today   = DateTime.current
    skip_logging = false

    if not json.blank? and json.is_a?(Hash)
      action = json['metaState'] 
      slave = account.slaves.not_deleted.where(comment: json['comment']).try(:first)
      serializer = API::V3::SlaveSerializer.new(json)

      unless slave.nil?
        logging = Logging.create(content: json, state: "INITIAL", loggerable: message, 
                       params: params, request_url: message.request_url, 
                       account: slave.try(:account), resourceable:slave)
      end
      
      unless slave.nil?
        check_order_duplicate(slave, json, action)        
        case action
        when "OPEN", "OPENED"
          slave.attributes = serializer.presenter_attributes
          if slave.remove?
            slave.execute
            slave.save
            slave.remove
          else
            slave.execute
          end
          @version = slave.versions.last
        when "CLOSED", "DELETED", "HASCLOSED"
          slave.attributes = serializer.presenter_attributes.merge(profit:json['profit']).except(:price_open)
          if action == "CLOSED" or action == "HASCLOSED"
            slave.close 
          else 
            slave.deleted
          end
          @version = slave.versions.last(2).try(:first)
        when "MODIFY"
          slave.set_sl_and_tp_order(*serializer.slave_attributes.values)
          @version = slave.versions.last
        when "MODIFY_VOLUME"
          @version = slave.versions.last
        when "NOTMODIFY"
          logging_count  = slave.loggings.where(state: action, ancestry: slave.loggings.last.ancestry, account_id: slave.account.id, created_at:date_today.beginning_of_day..date_today.end_of_day).count
          if logging_count >= 2
            action = "NOSLTP"
            @version = slave.versions.last
          end
        when "NOTFIND"
          slave.erro
          @version = slave.versions.last
        when "NOSLTP","ERRORDEAL","TIMEMAX", "NOTCLOSED", "REACHMFE", "REACHLOSS"
          if action == "NOSLTP" or action == "NOTCLOSED"
            @version = slave.versions.last
          else
            slave.erro
            @version = slave.versions.last
          end
          @version = slave.versions.last
        end
        logging.update(resourceable: slave, changeset: @version.try(:changeset), version:@version, state: action, parent: slave.loggings.first, loggerable: message)
      end
    end
    return true
  end

  def conciliate
    conciliate_inittial
    if json['ApiSendOrdersHistory'].to_b && account.api_send_orders_history
      ## TODO MELHORAR NUMA TRANSACAO DENTRO trace_ajust_profit
        message.execute if message.save
        message.loggings.create(content: json, state: "SLAVE/CONCILIATE", params: params, request_url: message.request_url, account: account, resourceable:account)
        trace_ajust_profit
      ## TODO MELHORAR
      account.update(api_send_orders_history: false)
    end
  end

  private

  def conciliate_inittial
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
    json_last    = jsons.last
    profit       = jsons.sum { |j| j["profit"].to_f }&.round(2)
    trace_id     = normalize_comment(json_last['comment'])&.first&.to_i&.abs
    fee          = jsons.sum{|j| j["fee"].to_f }&.round(2) 
    commission   = jsons.sum{|j| j["commission"].to_f }&.round(2) 
    swap         = jsons.sum {|j| j["swap"].to_f }&.round(2) 
    volume       = jsons.sum { |j| j["volume"].to_f }&.round(2) 
    fee          = fee + commission + swap
    trace        = Trace.find_by(id: trace_id) || find_or_create_trace
    slaves       = TransactionSlave.where(symbol: symbol, ticket_slave: positionID, account: account)

    maps = []
    results = []
    if slaves.present?
      slaves.each do |slave|    
        serializer = API::V3::SlaveSerializer.new(json_last)
        if slave && !slave.conciliated?
          order = slave.order || find_or_create_order(json_last, trace)
          results << update_existing_slave(slave, profit, fee, volume, serializer, trace, order)
        end
      end
    else
      order = find_or_create_order(json_last, trace)
      results << create_new_slave(symbol, positionID, json_last, profit, fee, volume, trace, order)
    end
    return results
  end

  def trace_ajust_profit
    trace  = find_or_create_trace
    profit = calculate_slaves_by(trace, :profit)
    fee    = calculate_slaves_by(trace, :fee)
    time   = @account.store.created_at.strftime("%Y.%m.%d %T")
    
    json_last = { "ticketMaster" => -1, "ticketSlave" => -1, "ticketDeal" => -1, "positionID" => -1, "type" => 0, "entry" => 0, "traceID" => 0,
             "slaveID" => 0, "magicNumber" => 0, "transactionID" => 0, "slipPage" => 0, "symbolDigits" => 0, "timeZone" => 0, "profit" => profit,
             "priceOpen" => 0, "priceClose" => 0, "priceRequest" => 0, "stopLoss" => 0, "takeProfit" => 0, "volume" => 0, "commission" => 0.00,
             "fee" => fee, "swap" => 0.00, "mae" => 0.00, "mfe" => 0.00, "state" => "closed", "metaAction" => "", "metaState" => "", "metaMessage" => "",
             "symbol" => "conciliated", "comment" => "-#{trace.id}#{@account.id}--#{-1}", "openAt" => time, "closeAt" => time, "timeGMT" => time, "timeTrader" => time
           }

    profit_conciliated = -1 * (profit - json['HistoryOrdersProfit'].to_f)&.round(2) 
    fee_conciliated    = -1 * (fee    - json['HistoryOrdersFee'].to_f)&.round(2) 

    order = find_or_create_order(json_last, trace)
    slave = trace.slaves.conciliated.find_by(symbol: 'conciliated', ticket_slave: -1, account: account)
    if slave.present?
      if profit_conciliated !=0 || fee_conciliated != 0
        serializer = API::V3::SlaveSerializer.new(json_last)
        update_existing_slave(slave, profit_conciliated, fee_conciliated, 0, serializer, trace, order)
      end
    else
      create_new_slave("conciliated", -1, json_last, profit_conciliated, fee_conciliated, 0, trace, order)
    end
  end

  def calculate_slaves_by(trace, kind = :profit)
    profit = 0
    fee    = 0
    @account.traces.each do |trace|
      profit += trace.slaves.sum(:profit)&.to_f
      fee    += trace.slaves.sum(:fee)&.to_f
    end

    if kind == :profit
      return profit.round(2)
    else
      return fee.round(2)
    end
  end

  def update_existing_slave(slave, profit, fee, volume, serializer, trace, order)
    if profit != slave.try(:profit).to_f || slave.lot.to_f != volume || slave.fee.to_f != fee
      slave.profit = profit
      slave.fee = fee.to_f
      slave.lot = volume.to_f
      slave.state = 'closed'
      slave.trace = trace
      slave.closed_at = serializer.closed_at if slave.closed_at.nil?
      slave.conciliated_at = Time.current

      if slave.save
        order.update(state: 'closed', conciliated_at: Time.current)
        order.slaves << slave unless order.slaves.exists?(slave.id)
        account.orders << order unless account.orders.exists?(order.id) 
        message.orders << order unless message.orders.exists?(order.id) 
        log_conciliation(slave, serializer.obj) 
        return true       
      end
    end
    return false
  end

  def create_new_slave(symbol, positionID, json_last, profit, fee, volume, trace, order)
    transaction = find_or_create_transaction(symbol, positionID, json_last, trace) unless symbol == 'conciliated'
    serializer = API::V3::SlaveSerializer.new(json_last)
    attributes = serializer.trace_attributes(symbol, account, nil, trace, account.store)
            .merge(
                   closed_at: serializer.closed_at,
                   price_open: serializer.price_open,
                   conciliated_at: Time.current,
                   open_at: serializer.open_at,
                   state: 'closed',
                   profit: profit.to_f,
                   fee: fee.to_f,
                   lot: volume,
                   comment: json_last["comment"] || "conciliate_order",
                 )
    slave = order.slaves.new(attributes)
    if slave.save
      order.slaves << slave unless order.slaves.exists?(slave.id)
      account.orders << order unless account.orders.exists?(order.id) 
      message.orders << order unless message.orders.exists?(order.id) 
      log_conciliation(slave, json_last)
      return true
    end
    return false
  end

  def normalize_comment(comment)
    comment.include?('--') ? comment&.split('--') : comment&.split('-')
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

    Order.find_by(symbol: json_last['symbol'], content_id: content_id, account: @account) || create_manual_order(json_last['symbol'], content_id, json_last, trace)
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

  def create_manual_order(symbol, content_id, json_last, trace)
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

  def log_conciliation(slave, content)
    logging = slave.loggings.new(
      state: "conciliated",
      content: content,
      resourceable: slave,
      changeset: slave.versions.try(:last).try(:changeset),
      version: slave.versions.try(:last),
      parent: slave.loggings.try(:first),
      request_url: message.request_url,
      account: account
    )
    logging.save
  end

  def check_order_duplicate(slave, json, action)
    content_id = normalize_comment(json['comment'])&.last&.to_i&.abs
    orders = Order.where(content_id: content_id, store: slave.store, account:slave.try(:master).try(:account), trace:slave.trace).where.not(id:slave.order.id)
    if orders.present?
      slave.loggings.create(content: orders&.map{|o|OrderSerializer.new(o)}, state: :ORDERDUPLICATE, parent: slave.loggings.first, account: slave.account, loggerable: message)                       
      orders.destroy_all
    end
    slaves = TransactionSlave.where(comment: json['comment'], store: slave.store, account:account, trace:slave.trace).where.not(id:slave.id)
    if slaves.present?
      slave.loggings.create(content: slaves&.map{|slave| slave.attributes}, state: :SLAVEDUPLICATE, parent: slave.loggings.first, account: slave.account, loggerable: message)                        
      slaves.destroy_all
    end
  end

end