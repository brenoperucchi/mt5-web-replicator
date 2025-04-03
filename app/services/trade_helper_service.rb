class TradeHelperService
  # attr_accessor :trace
  
  def self.magic_numbers_split(magic_numbers)
    delimiters = [',', ' ', "'",'-','_','.','/', ":", ";"]
    magic_numbers = magic_numbers.try(:split, (Regexp.union(delimiters))).try(:flatten)
    magic_numbers.reject! { |item| item.blank? } if magic_numbers
    (magic_numbers.blank? or magic_numbers.nil?) ? nil : magic_numbers
  end

  def self.api_request_attributes(resource, klass)
    ticket_master = ticketMaster(resource)
    ticket_slave = resource.try(:ticket_slave) || 0
    master_id  = resource.try(:master).try(:id) || 0
    deal_ticket = resource.try(:ticket_deal).blank? ? 0 : resource.ticket_deal
    seconds_ago = resource.try(:seconds_ago) || 0
    openprice = price_open(resource)
    trace_id = resource.trace_id
    openat = Rails.env.test? ? 0 : resource.try(:master).try(:open_at).to_i
    comment = resource.try(:comment)
    # comment = "#{trace_id}-#{ticket_master}"
    contract_volume = resource.try(:account).try(:contract_volume)
    "#{resource.ordertype}|#{ticket_master}|#{ticket_slave}|#{trace_id}|#{resource.id}|#{resource.magic_number}|#{master_id}|#{openprice}|#{resource.lot}|#{resource.stop_loss}|#{resource.take_profit}|#{resource.state}|#{resource.symbol}|#{deal_ticket}|#{seconds_ago}|#{comment}|#{openat}|#{contract_volume}"
  end
  

  def self.restrict_magic_number(klass, resource)
    unless resource.magics_accept.blank?
      resource_name_id = resource.try(:name)
      resource_name = resource.try(:name)
      magic_numbers = magic_numbers_split(resource.magics_accept)
      changeset = resource.try(:versions).try(:last).try(:changeset)
      version = resource.try(:version)
      if magic_numbers.detect{|x| x == klass.magic_number}.nil?
        klass.loggings.create(content:"#{resource.class.name} ##{resource.id} has magic number #{klass.magic_number} and the account: #{resource_name_id}##{resource_name} only accepted: #{magic_numbers.join(" - ")}", changeset: changeset, version:version, state: 'ERROR', parent:klass.message)
        klass.erro!
      end
    end
    klass.error?
  end 
  
  def self.api_request_attributes_scope(order, resource, scope)
    resource.send(scope).where('closed_at >=? OR closed_at is NULL', (Time.zone.now - 60.days)).collect{|t| t.api_request_attributes}.join('/')    
  end

  def self.ticketMaster(resource)
    ticket_master = resource.try(:ticket) || resource.try(:ticket_master)
    ticket_master.to_s.split('-').last
  end
  
  def self.price_open(resource)
    (resource.ordertype == "0" or resource.ordertype == 1) ? "0" : resource.price_request
  end
  
  def self.order_pending?
    self.content.upcase.include?('STOP') or self.content.upcase.include?('LIMIT')
  end

end