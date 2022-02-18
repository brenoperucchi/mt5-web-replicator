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

  def ticket
    obj['order_id']
  end

  def open_at
    Time.zone.at(obj['open_at'].try(:to_i))
  end

end
