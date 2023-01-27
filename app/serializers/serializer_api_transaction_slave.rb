class SerializerAPITransactionSlave < ActiveModel::Serializer
  
  def api_attributes
    {
      # symbol: symbol,
      ordertype: ordertype,
      lot: lot,
      price_open: price_open,
      price_closed: price_closed,
      magic_number: magic_number,
      stop_loss: stop_loss,
      take_profit: take_profit,
      # profit: profit,
      ticket_master: ticket_master,
      ticket_slave: ticket_slave,
      open_at: open_at,
      ticket_deal: obj['ticket_deal'],
      comment: obj['comment']
    }.compact
  end

  def obj
    if object.is_a?(Hash)
      object
    else
      YAML.load(object)
    end
  end

  def ordertype
    obj['type']
  end

  def lot
    obj['volume']
  end

  def price_open
    obj['price_open']
  end

  def price_closed
    obj['price_close'].to_f == 0 ? nil : obj['price_close']
  end

  def magic_number
    obj['magicnumber']
  end

  def stop_loss
    obj['stop_loss'].to_f
  end

  def take_profit
    obj['take_profit'].to_f
  end

  def ticket_master
    obj['ticket_id']
  end

  def ticket_slave
    obj['ticket_slave_id']
  end

  # def ticket_deal
  #   obj['deal_ticket']
  # end

  def open_at
    time = obj['open_at']
    time = time.to_s.include?(".") ? time.split(".").try(:first).to_i : time.to_i
    zone = obj['timezone'].try(:to_i)
    set_time_zone(time, zone)
  end

  def set_time_zone(time, zone)
    return 0 if time.nil?
    if zone.to_i != 0
     (Time.at(time).utc + zone.hours).to_datetime.change(:offset => Time.zone.formatted_offset)
    else
      Time.use_zone(Time.zone.name) { Time.zone.at(time).utc.to_datetime.change(offset: Time.zone.now.strftime("%z")) }
    end
    # return 0 if time == 0 
    # if zone.present? and zone != 0
    #   year  = Time.at(time).utc.strftime('%Y')
    #   month  = Time.at(time).utc.strftime('%m')
    #   day  = Time.at(time).utc.strftime('%d')
    #   hour  = Time.at(time).utc.strftime('%H').to_i - zone.abs
    #   minute  = Time.at(time).utc.strftime('%M')
    #   second  = Time.at(time).utc.strftime('%S')
    #   Time.zone.local(year, month, day, hour, minute, second).to_datetime

    # else
    #   Time.at(time).to_datetime
    # end
  end

end