class	API::V3::SlavePresenter < API::V3::BasePresenter

	API_VERSION = "v3"

	attr_accessor :params, :request, :response, :account, :message

	def initialize(params, request, message, account)
		@params 		 = params
		@request 		 = request
		@message 		 = message
		@account 		 = account
	end

	def slaves
	  # account = Account.find_by(name: params["account_id"], kind: :slave, state: :enable)
	  # if account
	  @response = account&.slaves&.opened&.where&.not(transaction_id: nil).where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 31.days))
	  																																    .collect { |t| t.api_request_attributes }.join('/')
	end


	def execute_status
	  map 				 = String.new
	  date_today 	 = DateTime.current
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
          slave.set_sl_and_tp_order(serializer)
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
        slave.loggings.create(content:json, changeset: @version.try(:changeset), version:@version, state: action, parent: slave.loggings.first, account: slave.account, loggerable: message, params: params, request_url: request.url) unless skip_logging
      end
	    if slave.nil?
	    	Logging.create(content: json, state: "ERRORSLAVE", loggerable: message, params: params, request_url: request.url)
	    end
	  end
		return true
	end

	def conciliate
	  slaves = account.transaction_slaves.not_executed
	  slave_profit = slaves.map(&:profit).compact.sum
	  if(json["HistoryOrdersProfit"].to_f != slave_profit.to_f and account.api_send_orders_history == false)
	    account.update(api_send_orders_history: true)
	  end

	  if(json["HistoryOrdersCount"].to_i == historyOrders.count)
	    if historyOrders.map { |h| h["profit"] }.sum.to_f != slave_profit.to_f
	      slaves.update_all(profit: 0)
	      account.loggings.create(state: "conciliated_account_zero", content: json, request_url: request.url)
	
	      slaves.each do |t| 
	        delete = false
	        historyOrders.each do |json| 
	          delete = json["ticketSlave"] == t.ticket_slave
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
	    slave = TransactionSlave.find_by(symbol: symbol, ticket_slave: json["ticketSlave"], account: account)
	    if slave
	      if slave.try(:profit).to_f != json["profit"].to_f
	        slave.profit = json["profit"].to_f
	        slave.save
	        change = true
	      end
	      # if slave.state == "pending" || slave.state == "executed"
	      #   slave.remove
	      #   change = true
	      # end
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
	      serializer = API::V3::SlaveSerializer.new(json)
	      attributes = serializer.trace_attributes(symbol, account, nil, trace, account.store)
	                     .merge(state: "closed", ticket_slave: json['positionID'], ticket_master: ticket_master, profit: json["profit"], comment: comment, open_at: json["openAt"], closed_at: json["closeAt"], price_open: json['priceOpen'])
	      slave = order.slaves.create(attributes)
	      change = true
	    end
	    if change
	      slave.loggings.create(state: "conciliated", content: json, resourceable: slave, changeset: slave.versions.try(:last).try(:changeset), version: slave.versions.try(:last), parent: slave.loggings.try(:first), request_url: request.url, account: account)
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