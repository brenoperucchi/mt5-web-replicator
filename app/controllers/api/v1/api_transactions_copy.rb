# require 'open-uri'
require 'json'
module API
  module V1
    class APITransactionsCopy < Grape::API
      include API::V1::Defaults

      resource :transactions do 
        # desc "Example Request Transaction"
        # get "/copy/trasmit/:expert_name/:expert_version/:account_id" do
        #   puts params
        #   account = Account.find_by(name: params[:account_id])
        #   if account
        #     map = account.slaves.executed.collect do |t| 
        #       attributes = t.meta_attributes
        #       "#{attributes[:trace_id]}|#{attributes[:instrument]}|#{attributes[:transaction_id]}|#{attributes[:ordertype]}|#{attributes[:openprice]}|#{attributes[:volume]}|#{attributes[:stoploss]}|#{attributes[:takeprofit]}|#{attributes[:magic_number]}"
        #     end.join('/')
        #   end
        #   content_type 'text/plain'
        #   body map
        # end

        desc "Receive Transaction"
        post "/copy/trasmit/:expert_name/:expert_version/:account_id/:account_mode" do
          map = String.new
          # orders = params[:orders]
          account = Account.find_by(name: params[:account_id], kind: :copy)
          if account# and params["orders"].present?
            
            account.loggings.create(content:params)
            trace = account.try(:trace_copy)

            if account.magics_accept.blank?
              magic_number = true
            else
              magic_number = account.magics_accept.try(:split).try(:include?, content['magic_number'])
            end

            if magic_number and trace #and not content.blank? and content.is_a?(Hash)
              # epoch_time = content['open_at'].split(".").first.to_i
              # d = Time.at(epoch_time).utc.to_datetime
              # content_at = Time.new(d.year, d.month, d.day,d.hour,d.minute,d.second, "-03:00").to_datetime
              # create(content: params, content_id: comment, content_at: content_at, store: trace.store)
              orders = {orders:[]}
              params['orders'].split("//").each do |order| 
                orders[:orders] << [YAML.load(order)]
              end
              orders[:params] = params.except('orders')
              message = Message::Metatrader.create(content: orders.to_json, content_at: Time.zone.now, store: trace.store, trace:trace)
              message.prepare
              message.execute
            end
          end
          content_type 'text/plain'
          body map
        end

        #   map = String.new
        #   params_body = params[:body]
        #   binding.pry
        #   content = YAML.load(params_body)
        #   print(content)
        #   account = Account.find_by(name: params[:account_id], kind: :copy)

        #   return if account.nil?
        #   account.loggings.create(content:params_body)

        #   trace = account.try(:trace_copy)

        #   if account.magics_accept.blank?
        #     magic_number = true
        #   else
        #     magic_number = account.magics_accept.try(:split).try(:include?, content['magic_number'])
        #   end
          
        #   if magic_number and trace and not content.blank? and content.is_a?(Hash)
        #     case content['action']
        #     when "OPEN"
        #       comment = content['comment']
        #       epoch_time = content['open_at'].split(".").first.to_i
        #       d = Time.at(epoch_time).utc.to_datetime
        #       # content_at = Time.zone.local(d.year,d.month,d.day,d.hour,d.minute,d.second)

        #       content_at = Time.new(d.year, d.month, d.day,d.hour,d.minute,d.second, "-03:00").to_datetime
        #       # content_at = Time.at(epoch_time.to_i).utc.to_datetime
        #       # Time.zone = "GMT"
        #       # Time.zone.at(epoch_time.to_i)
        #       # Time.zone = "Brasilia"
        #       # Time.zone.at(epoch_time.to_i)
        #       message = trace.messages.create(content: params_body, content_id: comment, content_at: content_at, store: trace.store)
        #       message.prepare
        #       if message.transactions
        #         message.transactions.each do |t|
        #           t.loggings.create(content:params_body)
        #           t.update(ticket: content['order_ticket'], price_open:content['open_price'], open_at: Time.at(content['open_at'].split(".").first.to_i))
        #           map = "#{t.order.trace.id}|#{t.id}|OK"
        #         end
        #       end
        #     when "MODIFY","CLOSE"
        #       ticket_id = content['order_ticket']
        #       transaction = Transaction.find_by(ticket: ticket_id)
        #       return if transaction.nil?
        #       transaction.loggings.create(content:params_body)
        #       if content['action'] == "MODIFY"
        #         transaction.set_all_sl_and_tp_order(take_profit=content['take_profit'], stop_loss=content['stop_loss'])
        #       else
        #         transaction.update(profit: content['profit'])
        #         transaction.close_copy                
        #       end
        #       map = "#{transaction.order.trace.id}|#{transaction.id}|OK"
        #     when "LOT_IN"
        #       ticket_id = content['order_ticket']
        #       transaction = Transaction.find_by(ticket: ticket_id)
        #       return if transaction.nil?
        #       transaction.loggings.create(content:params_body)
        #       volume = (transaction.account.sum_slaves_volume(transaction.id).to_f - content['volume'].to_f).abs
        #       comment = transaction.slaves.first.comment
        #       transaction.order.trace.accounts.slave.each do |account|
        #         if transaction.ordertype == "0"
        #           t = account.slaves.create(transaction.attributes.merge(master: transaction, ordertype:0, lot:volume, state:"pending", created_at: Time.zone.now, comment: comment).except("message_id", "close_at", "id")) 
        #         elsif transaction.ordertype == "1"
        #           account.slaves.create(transaction.attributes.merge(master: transaction, ordertype:1, lot:volume, state:"pending", created_at: Time.zone.now, comment: comment).except("message_id", "close_at", "id")) 
        #         end
        #       end
        #     when "LOT_OUT"
        #       ticket_id = content['order_ticket']
        #       transaction = Transaction.find_by(ticket: ticket_id)
        #       return if transaction.nil?
        #       transaction.loggings.create(content:params_body)
        #       volume = content['volume'].to_f - transaction.account.sum_slaves_volume(transaction.id).to_f
        #       transaction.order.trace.accounts.slave.each do |account|
        #         if transaction.ordertype == "0"
        #           account.slaves.create(transaction.attributes.merge(master: transaction, ordertype:1, lot:volume, state:"pending", created_at: Time.zone.now).except("message_id", "close_at", "id")) 
        #         elsif transaction.ordertype == "1"
        #           account.slaves.create(transaction.attributes.merge(master: transaction, ordertype:0, lot:volume, state:"pending", created_at: Time.zone.now).except("message_id", "close_at", "id")) 
        #         end
        #       end
        #     end
        #   end
        #   content_type 'text/plain'
        #   body map
        # end
        # ##############################################
      end
    end
  end
end