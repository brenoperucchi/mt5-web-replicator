class APITransactionSerializer < ActiveModel::Serializer
  
  def api_attributes
    {
      symbol: symbol,
      ordertype: ordertype,
      lot: lot,
      price_open: price_open,
      magic_number: magic_number,
      stop_loss: stop_loss,
      take_profit: take_profit,
      profit: profit,
      ticket: ticket,
      open_at: open_at
    }
  end

  def obj
    YAML.load(object)
  end

  def symbol
    obj['order_symbol']
  end

  def ordertype
    obj['order_type']
  end

  def lot
    obj['volume']
  end

  def price_open
    obj['open_price']
  end

  def magic_number
    obj['magic_number']
  end

  def stop_loss
    obj['stop_loss']
  end

  def take_profit
    obj['take_profit']
  end

  def profit
    obj['profit']
  end

  def trace_id
    obj['comment'].split('|').first
  end

  def transaction_id
    obj['comment'].split('|').last
  end

  def ticket
    obj['order_ticket']
  end

  def open_at
    Time.at(obj['open_at'].try(:split, ".").try(:first).try(:to_i))
  end

end
