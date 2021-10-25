require File.expand_path('../../../config/environment', __FILE__)
# load "#{Rails.root}/lib/telegram/signal.rb"
require 'rubygems'
require 'ffi-rzmq'

def checkTransaction(content)
  transaction_id = content['comment'].split("|").last
  return false if transaction_id.nil?
  
  transaction = nil
  count = 1
  
  while transaction.nil? and count <= 20
    count+=
    sleep(0.2)
    transaction = Transaction.find_by(id: transaction_id)
    break if transaction
    puts("OBJECT ID->#{transaction.try(:id)}")
  end
  return transaction
end


def main
  ctx = ZMQ::Context.new
  pull_socket   = ctx.socket ZMQ::PULL
  pub_socket    = ctx.socket ZMQ::PUB
  pull_socket.bind("tcp://0.0.0.0:5550")
  # pub_socket.connect("tcp://0.0.0.0:5559")
  # pull_socket.setsockopt(zmq.RCVHWM, 1)
  # pull_socket.setsockopt(ZMQ::LINGER, 0)

  loop do
    sleep(2)
    message = ''
    pull_socket.recv_string(message, 0)
    content = YAML.load(message)
    if not content.blank? and content.is_a?(Hash)
      print(message)
      case content['action']
      when "COPY"
        trace_id = content['magic_number']
        comment = content['comment']
        time_at = Time.at(content['open_at'].split(".").first.to_i)
        for i in 1..100 do
          sleep(0.2)
          trace = Trace.find_by(id: trace_id)
          break if trace
        end
        message = trace.messages.create(content: message, content_id: comment, content_at: time_at, store: trace.store)
        message.prepare
      when "COPY MODIFY"
        ticket_id = content['order_ticket']
        for i in 1..100 do
          sleep(0.2)
          transaction = Transaction.find_by(ticket: ticket_id)
          break if transaction
        end
        if transaction
          transaction.loggings.create(content:message)
          transaction.set_sl_and_tp_order(content['take_profit'], content['stop_loss'])
        end
      when "COPY CLOSE"
        ticket_id = content['order_ticket']
        for i in 1..100 do
          sleep(0.2)
          transaction = Transaction.find_by(ticket: ticket_id)
          break if transaction
        end
        if transaction
          transaction.loggings.create(content:message)
          transaction.close_order
        end
      when "CLOSED"
          transaction = checkTransaction(content)
          if transaction
            transaction.loggings.create(content:message)
            transaction.close
            # order = "#{transaction_id} SLAVE CLOSED|#{transaction.symbol}|#{content['order_ticket']}|#{transaction.ordertype}|#{transaction.price_request}|0.0|#{transaction.lot}|#{transaction.stop_loss}|#{transaction.take_profit}"
            # pub_socket.send_string(order)
          end
      when "MODIFY"
          transaction = checkTransaction(content)
          if transaction
            transaction.loggings.create(content:message)
            transaction.update(stop_loss:content['stop_loss'], take_profit:content['take_profit'])
          end
      when "OPENED"
          transaction = checkTransaction(content)
          if transaction
            transaction.loggings.create(content:message)
            transaction.slaves.create(ticket:content['order_ticket'], price_open:content['open_price'],
                                      open_at: Time.at(content['open_at'].split(".").first.to_i), 
                                      comment: content['comment'])
            # order = "#{transaction_id} SLAVE OPEN|#{transaction.symbol}|#{content['order_ticket']}|#{transaction.ordertype}|#{transaction.price_request}|0.0|#{transaction.lot}|#{transaction.stop_loss}|#{transaction.take_profit}"
            # pub_socket.send_string(order)
          end
      when "LOGIN"
         store = Store.all.detect{|x| x.master.include?(content['account_login'])}
        if store.present?
          attributes = "#{content['account_login']}|1"
        else
          attributes = "#{content['account_login']}|0"
        end
          pub_socket.send_string(attributes)
      end
    end
  end
end

self.main