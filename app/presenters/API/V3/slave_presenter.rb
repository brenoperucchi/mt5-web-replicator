class API::V3::SlavePresenter < API::V3::BasePresenter

  API_VERSION = "v3"

  attr_accessor :params, :request, :response, :account, :message

  def initialize(params, message, account)
    @params      = params
    @message     = message
    @account     = account
  end

  def slaves
    # account = Account.find_by(name: params["account_id"], kind: :slave, state: :enable)
    # if account
    @response = account&.slaves&.opened&.where&.not(transaction_id: nil).where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 31.days))
                                                                        .collect { |t| t.api_request_attributes }.join('/')
  end


  def execute_status
    map          = String.new
    date_today   = DateTime.current
    skip_logging = false

    if not json.blank? and json.is_a?(Hash)
      action = json['metaState'] 
      slave = account.slaves.not_deleted.where(comment: json['comment']).first
      serializer = API::V3::SlaveSerializer.new(json)

      unless slave.nil?
        check_order_duplicate(slave, json, action)        
        case action
        when "OPEN", "OPENED"
          slave.attributes = serializer.presenter_attributes
          slave.execute
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
            skip_logging = true if slave.loggings.where(state: action, created_at:date_today.beginning_of_day..date_today.end_of_day).present?                    
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
        logging_content = nil
        slave.loggings.create(content:json, changeset: @version.try(:changeset), version:@version, state: action, parent: slave.loggings.first, account: slave.account, loggerable: message, params: params, request_url: message.request_url) unless skip_logging
      end
      if slave.nil?
        Logging.create(content: json, state: "ERRORSLAVE", loggerable: message, params: params, request_url: message.request_url)
      end
    end
    return true
  end

  def conciliate
    slaves = account.transaction_slaves.not_error
    slave_profit = slaves.map(&:profit).compact.sum.round(2).to_f

    if account.api_send_orders_history and json["HistoryOrdersProfit"].to_f != slave_profit
      historyOrders.group_by{|h| [h["positionID"],h["symbol"]]}.each do |(positionID, symbol), jsons|
        change = false
        json_last = jsons.last
        slave = TransactionSlave.find_by(symbol: symbol, ticket_slave: positionID, account: account)
        profit = jsons.sum{|j| j["profit"]}.round(2)
        volume = jsons.sum{|j| j["volume"]}
        serializer = API::V3::SlaveSerializer.new(json_last)
        
        if slave
          if profit != slave.try(:profit).to_f
            slave.profit = profit
            slave.lot    = volume
            slave.closed_at = serializer.closed_at if slave.closed_at.nil?
            slave.save
            change = true
          end
        else
          order = Order.find_by(symbol: symbol, content_id: positionID)
          ticket_master = 0
          if order
            trace = order.trace
            comment = json_last["ticketMaster"]
          else
            comment = "conciliate_order"
            trace = Trace.create_with(name: "manual_orders", name_id: -1, store: account.store, kind: 2, contract_volume_max: 1, customer_plans: [account.store.customer_plans.first])
                        .find_or_create_by(name: "manual_orders", name_id: -1)
            order = Order.create(symbol: symbol, content: json_last, content_id: ticket_master, account: account, state: 'conciliated', store: account.store, trace: trace)
          end
          serializer = API::V3::SlaveSerializer.new(json_last)
          attributes = serializer.trace_attributes(symbol, account, nil, trace, account.store)
                         .merge(state: "closed", ticket_slave: json_last['positionID'], ticket_master: ticket_master, profit: profit, comment: comment, open_at: json_last["openAt"], closed_at: json_last["closeAt"], price_open: json_last['priceOpen'], lot: volume)
          slave = order.slaves.create(attributes)
          change = true
        end
        if change
          message.save
          message.conciliate
          slave.loggings.create(state: "conciliated", content: json_last, resourceable: slave, changeset: slave.versions.try(:last).try(:changeset), version: slave.versions.try(:last), parent: slave.loggings.try(:first), request_url: message.request_url, account: account, loggerable: message)
        end
      end
      account.update(api_send_orders_history: false) if account.api_send_orders_history
    else
      slaves = account.transaction_slaves.not_error
      slave_profit = slaves.map(&:profit).compact.sum.round(2).to_f
      
      if(json["HistoryOrdersCount"].to_i == historyOrders.count)
        if json["HistoryOrdersProfit"].to_f != slave_profit #and json["HistoryOrdersCount"].to_i == slaves.count
          slaves.update_all(profit: 0)
          account.loggings.create(state: "conciliated_account_zero", content: json, request_url: message.request_url)
        end
        account.update(api_send_orders_history: false) if account.api_send_orders_history
      end

      if(json["HistoryOrdersProfit"].to_f != slave_profit and account.api_send_orders_history == false)
        account.update(api_send_orders_history: true)
      end
    end
  end
  
  private
    def check_order_duplicate(slave, json, action)
      orders = Order.where(content_id: json['comment'].try(:to_i), store: slave.store, account:slave.try(:master).try(:account), trace:slave.trace).where.not(id:slave.order.id)
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