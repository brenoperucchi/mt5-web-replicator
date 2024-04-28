class SerializerAPITransactionSlave < ActiveModel::Serializer
  
  def api_attributes
    {
      # symbol: symbol,
      ticket_master: ticket_master,
      ticket_slave: ticket_slave,
      ticket_deal: obj['ticket_deal'],
      ordertype: ordertype,
      lot: lot,
      price_open: price_open,
      price_closed: price_closed,
      stop_loss: stop_loss,
      take_profit: take_profit,
      profit: obj['profit'],
      comment: obj['comment'],
      magic_number: magic_number,
      open_at: open_at,
      closed_at: closed_at,
    }.compact
  end

  def trace_attributes(instrument, account_slave, master, trace)
    {
      symbol: instrument,
      ticket_master: ticket_master,
      ticket_slave: ticket_slave,
      ticket_deal: obj['ticket_deal'],
      ordertype: ordertype,
      lot: lot,
      price_open: 0,
      price_closed: price_closed,
      price_request: obj['price'],
      stop_loss: stop_loss,
      take_profit: take_profit,
      profit: 0,
      comment: ticket_master,
      magic_number: magic_number,
      account: account_slave,
      master: master,
      trace: trace,
      open_at: nil,
      closed_at: nil,
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
    obj['magic_number'] || obj['magicnumber']
  end

  def stop_loss
    obj['stop_loss']
  end

  def take_profit
    obj['take_profit']
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

  def closed_at
    update_time_zone((obj['closed_at'] || obj['close_at']))
  end

  def open_at
    update_time_zone(obj['open_at'])
  end

  def update_time_zone(time_at)
    return nil if time_at.blank?
    time_zone_diff(obj['time_gmt'], obj['time_trader'], time_at)
  end

  def time_zone_diff(time_gmt, time_trader, time_at)
    # Calculate timezone difference in hours
    trader_time = DateTime.parse(time_trader)
    gmt_time = DateTime.parse(time_gmt)
    time_zone_hours = ((trader_time.to_time - gmt_time.to_time) / 1.hour).round

    # Parse the 'time_at' and adjust for the timezone
    parsed_time = DateTime.parse(time_at)
    adjusted_time = parsed_time - time_zone_hours.hours

    # Return the adjusted time
    adjusted_time
  end

  # def update_time_zone(time_at)
  #   return nil if time_at.nil? or time_at.empty?
  #   time = time_at
  #   time = time.to_s.include?(".") ? time.split(".").try(:first).to_i : time.to_i
  #   zone = obj['timezone'].try(:to_i)

  #   unless obj.key?("time_trader")
  #     set_time_zone(time, zone)
  #   else
  #     time_zone(obj['time_gmt'], obj['time_trader'], time_at)
  #   end
  # end

  # def set_time_zone(time, zone)
  #   return 0 if time.nil?
  #   if zone.to_i != 0
  #    (Time.at(time).utc + zone.hours).to_datetime.change(:offset => Time.zone.formatted_offset)
  #   else
  #     Time.use_zone(Time.zone.name) { Time.zone.at(time).utc.to_datetime.change(offset: Time.zone.now.strftime("%z")) }
  #   end
  # end

  # def time_zone(time_gmt, time_trader, time_at)
  #   time_zone = ((DateTime.parse(time_trader).to_i - DateTime.parse(time_gmt).to_i).to_f/3600).round
  #   time_gmt = DateTime.parse(time_at + time_zone.to_sign) 
  #   time_gmt.in_time_zone
  # end

end