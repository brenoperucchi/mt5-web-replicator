class APITransactionSlaveSerializer < ActiveModel::Serializer
  
  def api_attributes
    {
      # symbol: symbol,
      ordertype: ordertype,
      lot: lot,
      price_open: price_open,
      magic_number: magic_number,
      stop_loss: stop_loss,
      take_profit: take_profit,
      # profit: profit,
      ticket_master: ticket_master,
      ticket_slave: ticket_slave,
      open_at: open_at,
      # ticket_deal: ticket_deal,
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

  # def symbol
  #   obj['order_symbol']
  # end

  def ordertype
    obj['type']
  end

  def lot
    obj['lot']
  end

  def price_open
    obj['price']
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

  # def profit
  #   obj['profit']
  # end

  # def trace_id
  #   obj['comment'].split('|').first
  # end

  # def transaction_id
  #   obj['comment'].split('|').last
  # end

  def ticket_master
    obj['order_id']
  end

  def ticket_slave
    obj['ticket_slave_id']
  end

  # def ticket_deal
  #   obj['deal_ticket']
  # end

  def open_at
    Time.zone.at(obj['open_at'].try(:to_i)).in_time_zone(obj['timezone']).to_datetime.change(:offset => Time.zone.formatted_offset)
  end

end
