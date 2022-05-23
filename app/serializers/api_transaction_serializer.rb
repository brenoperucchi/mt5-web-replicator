class APITransactionSerializer < ActiveModel::Serializer
  
  def api_attributes
    {
      ordertype: ordertype,
      lot: lot,
      price_open: price_open,
      magic_number: magic_number,
      stop_loss: stop_loss,
      take_profit: take_profit,
      ticket: ticket,
      open_at: open_at,
      comment: obj['comment']
    }
  end

  def obj
    object
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

  def magic_number
    obj['magicnumber']
  end

  def stop_loss
    obj['stoploss']
  end

  def take_profit
    obj['takeprofit']
  end

  def ticket
    obj['order_id']
  end

  def open_at
    time = obj['open_at'].try(:to_i)
    zone = obj['timezone']
    set_time_zone(time, zone)
  end

  def set_time_zone(time, zone)
    if zone.to_i != 0
      Time.zone.at(time).in_time_zone(zone).to_datetime.change(:offset => Time.zone.formatted_offset)
    else
      Time.use_zone(Time.zone.name) { Time.zone.at(time).utc.to_datetime.change(offset: Time.zone.now.strftime("%z")) }
    end
  end

end
