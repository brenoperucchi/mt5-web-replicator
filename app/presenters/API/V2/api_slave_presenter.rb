class	API::V2::APISlavePresenter 

	def self.check_order_duplicate(slave, content, action)
		orders = Order.where(content_id: content['comment'].try(:to_i), store: slave.store, account:slave.try(:master).try(:account), trace:slave.trace).where.not(id:slave.order.id)
		if orders.present?
			slave.loggings.create(content: orders&.map{|o|OrderSerializer.new(o)}, state: :ORDERDUPLICATE, parent: slave.loggings.first, account: slave.account, loggerable: slave.order.messages.last)												
			orders.destroy_all
		end
	end

	def self.api_slave(params, version, request)
	  map = String.new
	  message = params[:body]
	  content = YAML.load(message)
	  date_today = DateTime.current
	  skip_logging = false

	  if not content.blank? and content.is_a?(Hash)
	    action = content['meta_state']
	    account_server = AccountServer.find_or_create_by(name: params[:account_server_name].try(:downcase))
	    account = Account.find_by(name: params[:account_id], account_server: account_server, state: :enable, kind: :slave)
	    if account
	      slave = account.slaves.not_deleted.where(comment: content['comment']).first

				self.check_order_duplicate(slave, content, action)	      

	      unless slave.nil?
	        case action
	        when "OPEN", "OPENED"
	          api_attributes = SerializerAPITransactionSlave.new(message).api_attributes
	          slave.attributes = api_attributes
	          slave.execute
	          @version = slave.versions.last
	          map = "#{slave.master.trace.id}|#{slave.id}|OK"
	        when "CLOSED", "DELETED", "HASCLOSED"
	        	api_attributes = SerializerAPITransactionSlave.new(message).api_attributes.merge(profit:content['profit']).except(:price_open)
	        	# if account.hedging?
	        	#   slave1 = account.slaves.find_by(ticket_master: api_attributes[:comment], ticket_slave: api_attributes[:ticket_slave], state: "executed")
	        	#   # slave ||= account.slaves.find_by(comment: api_attributes[:comment])
	        	#   slave2 ||= account.slaves.where(ticket_master: api_attributes[:comment], ticket_slave:nil, state: "pending").take
	        	#   if slave1.nil? and slave2.nil?
	        	#     api_attributes = SerializerAPITransactionSlave.new(message).api_attributes
	        	#     slave = account.slaves.find_by(comment: content['comment']).dup
	        	#     slave.attributes = api_attributes
	        	#     if slave.save
	        	#       @version = slave.versions.last
	        	#       slave.loggings.create(content:message, changeset: @version.try(:changeset), version:@version, state: "DUPLICATE")
	        	#     else
	        	#       Logging.create(content:message, state: "NOTDUPLICATE", parent: order.try(:message).try(:loggings).try(:first), account: account)
	        	#     end
	        	#   end
	        	# end
	          slave.attributes = api_attributes	          
	          # if slave.closed? and slave.loggings.count < 4 and slave.loggings.detect(&:detect_closed?).nil?
	          #   slave.state = :executed
	          #   slave.master.state = :executed
	          # end                  
	          # action == "CLOSED" ? slave.close : slave.deleted
	          if action == "CLOSED" or action == "HASCLOSED"
	            slave.close 
	          else 
	            slave.deleted
	          end
	          @version = slave.versions.last(2).try(:first)
	          map = "#{slave.master.trace.id}|#{slave.id}|OK"
	        when "MODIFY"
	          slave.set_sl_and_tp_order(nil, content['take_profit'], content['stop_loss'])
	          @version = slave.versions.last
	          map = "#{slave.master.trace.id}|#{slave.id}|OK"
	        when "MODIFY_VOLUME"
	          @version = slave.versions.last
	          map = "#{slave.master.trace.id}|#{slave.id}|OK"                  
	        when "NOTMODIFY"
	          logging_count  = slave.loggings.where(state: action, ancestry: slave.loggings.last.ancestry, account_id: slave.account.id, created_at:date_today.beginning_of_day..date_today.end_of_day).count
	          if logging_count >= 2
	            action = "NOSLTP"
	            skip_logging = true if slave.loggings.where(state: action, created_at:date_today.beginning_of_day..date_today.end_of_day).present?                    
	            # api_attributes = SerializerAPITransactionSlave.new(message).api_attributes.merge(stop_loss:0, take_profit:0).except(:price_open, :price_closed)
	            # slave.attributes = api_attributes
	            # slave.save
	            @version = slave.versions.last
	          end
	        when "NOTFIND"
	          slave.erro
	          @version = slave.versions.last
	        when "NOSLTP","ERRORDEAL","TIMEMAX", "NOTCLOSED", "REACHMFE", "REACHLOSS"
	          if action == "NOSLTP" or action == "NOTCLOSED"
	            # skip_logging = true if slave.loggings.where(state: action, created_at:date_today.beginning_of_day..date_today.end_of_day).present?
	            # api_attributes = SerializerAPITransactionSlave.new(message).api_attributes.merge(stop_loss:0, take_profit:0).except(:price_open, :price_closed)
	            # slave.attributes = api_attributes
	            # slave.save
	            @version = slave.versions.last
	          else
	            api_attributes = SerializerAPITransactionSlave.new(message).api_attributes
	            slave.erro
	            @version = slave.versions.last
	          end
	          @version = slave.versions.last
	          map = "#{slave.master.trace.id}|#{slave.id}|OK"
	        end
	        logging_content = nil
	        # message << params.except("body").to_s.delete('\\"')
	        slave.loggings.create(content:message, changeset: @version.try(:changeset), version:@version, state: action, parent: slave.loggings.first, account: slave.account, loggerable: slave.order.messages.last) unless skip_logging
	      end
	    else
	      Logging.create(content:message, state: action)
	    end
	    return map
	  end
	end
end