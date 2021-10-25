require 'rubygems'
require 'ffi-rzmq'

# if ARGV.length < 3
#   puts "usage: ruby local_lat.rb <connect-to> <message-size> <roundtrip-count>"
#   exit
# end

# bind_to = ARGV[0]
# bind_to = "tcp://0.0.0.0:5555"

# message_size = ARGV[1].to_i
roundtrip_count = 10

ctx = ZMQ::Context.new()
sender   = ctx.socket ZMQ::PUB
# sender   = ctx.socket ZMQ::PUSH
# receiver   = ctx.socket ZMQ::PUB
# rc  = s.setsockopt(ZMQ::SNDHWM)
# rc  = s.setsockopt(ZMQ::RCVHWM)
rs  = sender.bind("tcp://0.0.0.0:5558")
# rr  = receiver.bind("tcp://0.0.0.0:5551")

while true
  msg = "Server PUB2"
  # raise "Message size doesn't match, expected [#{message_size}] but received [#{msg.size}]" if message_size != msg.size
  message_sender  = sender.send_string msg, 0
  # message_receive  = sender.recv_string msg
  # print message_receive 

  # AccountInfoInteger(ACCOUNT_LOGIN),
  # "CLOSED",
  # OrderSymbol(), 
  # OrderTicket(),
  # OrderType(), 
  # OrderOpenPrice(),
  # OrderClosePrice(),
  # OrderLots(), 
  # OrderStopLoss(), 
  # OrderTakeProfit()
  # order = "45103444 OPEN|EURUSD|000001|OP_BUY|0.0|0.0|0.1|0.0|0.0"
  # message_sender  = sender.send_string order, 0

              #   AccountInfoInteger(ACCOUNT_LOGIN),
              # "OPEN",
              # OrderSymbol(), 
              # OrderTicket(),
              # OrderType(), 
              # OrderOpenPrice(),
              # OrderClosePrice(),
              # OrderLots(), 
              # OrderStopLoss(), 
              # OrderTakeProfit()
end