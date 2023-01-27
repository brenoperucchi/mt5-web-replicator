class SerializerAPITransaction < ActiveModel::Serializer
  
  def api_attributes
    {
      ordertype: ordertype,
      lot: lot,
      price_open: price_open,
      # price_closed: price_closed,
      magic_number: magic_number,
      stop_loss: stop_loss,
      take_profit: take_profit,
      ticket: ticket,
      open_at: open_at,
      comment: obj['comment'],
      ticket_deal: obj['ticket_deal'],
    }
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
    obj['open_price']
  end

  # def price_closed
  #   obj['close_price']
  # end

  def magic_number
    obj['magicnumber']
  end

  def stop_loss
    obj['stop_loss'].to_f
  end

  def take_profit
    obj['take_profit'].to_f
  end

  def ticket
    obj['ticket_id']
  end

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
  end

end
