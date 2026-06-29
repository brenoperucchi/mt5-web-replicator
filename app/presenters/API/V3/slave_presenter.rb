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

  def normalize_comment(comment)
    comment.include?('--') ? comment&.split('--') : comment&.split('-')
  end
  
end