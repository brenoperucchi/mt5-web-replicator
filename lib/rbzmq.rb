require 'rubygems'
require 'ffi-rzmq'

if ARGV.length < 3
  puts "usage: ruby local_lat.rb <connect-to> <message-size> <roundtrip-count>"
  exit
end

bind_to = ARGV[0]
# message_size = ARGV[1].to_i
roundtrip_count = ARGV[2].to_i

ctx = ZMQ::Context.new
s   = ctx.socket ZMQ::REP
# rc  = s.setsockopt(ZMQ::SNDHWM)
# rc  = s.setsockopt(ZMQ::RCVHWM)
rc  = s.bind(bind_to)

roundtrip_count.times do
  msg = ""
  rc  = s.recv_string msg
  # raise "Message size doesn't match, expected [#{message_size}] but received [#{msg.size}]" if message_size != msg.size
  rc  = s.send_string msg, 0
end