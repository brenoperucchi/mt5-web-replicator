# require 'tdlib-ruby'
# require 'apisocial/telegram'
class Connection# < ApplicationRecord
  # include Telegram

  def initialize
    @sender_user_id = '487330707'.to_i

    @telegram = Apisocial::Telegram.new
    @telegram = @telegram.client
    # @client
  end

  def get_ticket(chat_id=487330707)
    @telegram.get_chat_history(chat_id,0,0,10,true).result[1]  
  end

  def get_message
    ticket = get_ticket
		message = ticket.messages.first
    if message.sender_user_id == @sender_user_id
      message.content.text.text.strip_emoji
    else
      return false
    end
  end


  def attributes_signal(message)
    return nil unless message
    #to-do check currency enable on system
    currency = message[0..5]
    
    #todo Now and Price should be a price to bid
    price = message.gsub("@","")

    kind = if message.include?("sell") then "sell" else "buy" end
    stop_loss = message.match(/Sl(.*?$)/m)[1].gsub("@","")
    take_profit1 = message.match(/Tp1(.*?$)/m)[1].gsub("@","")
    take_profit2 = message.match(/Tp2(.*?$)/m)[1].gsub("@","")
    { currency: currency, kind: kind, price: price, stop_loss: stop_loss, take_profit1: take_profit1, 
      take_profit2: take_profit2 } 
  end

  def record_signal
    values = attributes_signal(get_message)
    Sign.create(values) if values
  end

end