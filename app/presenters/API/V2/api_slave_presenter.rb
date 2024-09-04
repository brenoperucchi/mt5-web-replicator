class	API::V2::APISlavePresenter 

	def self.check_order_duplicate(slave, content, action)
		orders = Order.where(content_id: content['comment'].try(:to_i), store: slave.store, account:slave.try(:master).try(:account), trace:slave.trace).where.not(id:slave.order.id)
		if orders.present?
			slave.loggings.create(content: orders&.map{|o|OrderSerializer.new(o)}, state: :ORDERDUPLICATE, parent: slave.loggings.first, account: slave.account, loggerable: slave.order.messages.last)												
			orders.destroy_all
		end
	end

	def self.api_slave(params, api_version, request)
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
				serializer = API::V2::SlaveSerializer.new(message)

	      unless slave.nil?
					self.check_order_duplicate(slave, content, action)	      
	        case action
	        when "OPEN", "OPENED"
	          slave.attributes = serializer.api_attributes
	          slave.execute
	          @version = slave.versions.last
	          map = "#{slave.master.trace.id}|#{slave.id}|OK"
	        when "CLOSED", "DELETED", "HASCLOSED"
	          slave.attributes = serializer.api_attributes.merge(profit:content['profit']).except(:price_open)
	          if action == "CLOSED" or action == "HASCLOSED"
	            slave.close 
	          else 
	            slave.deleted
	          end
	          @version = slave.versions.last(2).try(:first)
	          map = "#{slave.master.trace.id}|#{slave.id}|OK"
	        when "MODIFY"
	          slave.set_sl_and_tp_order(serializer)
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
	            @version = slave.versions.last
	          end
	        when "NOTFIND"
	          slave.erro
	          @version = slave.versions.last
	        when "NOSLTP","ERRORDEAL","TIMEMAX", "NOTCLOSED", "REACHMFE", "REACHLOSS"
	          if action == "NOSLTP" or action == "NOTCLOSED"
	            @version = slave.versions.last
	          else
	            # slave.attributes = serializer.api_attributes
	            slave.erro
	            @version = slave.versions.last
	          end
	          @version = slave.versions.last
	          map = "#{slave.master.trace.id}|#{slave.id}|OK"
	        end
	        logging_content = nil
	        slave.loggings.create(content:message, changeset: @version.try(:changeset), version:@version, state: action, parent: slave.loggings.first, account: slave.account, loggerable: slave.order.messages.last) unless skip_logging
	      end
	    else
	      Logging.create(content:message, state: action)
	    end
	    return map
	  end
	end
end