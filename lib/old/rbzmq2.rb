require 'rubygems'
require 'ffi-rzmq'


def error_check(rc)
  if ZMQ::Util.resultcode_ok?(rc)
    false
  else
    STDERR.puts "Operation failed, errno [#{ZMQ::Util.errno}] description [#{ZMQ::Util.error_string}]"
    caller(1).each { |callstack| STDERR.puts(callstack) }
    true
  end
end



send_url = "tcp://0.0.0.0:5555"
receive_url = "tcp://0.0.0.0:5556"
# message_size = ARGV[1].to_i
# roundtrip_count = ARGV[2].to_i

ctx = ZMQ::Context.create(1)
STDERR.puts "Failed to create a Context" unless ctx

#Lets set ourselves up for replies
rep_sock = ctx.socket(ZMQ::REP)
rc = rep_sock.bind(send_url)
error_check(rc)
  

# ctx = ZMQ::Context.new()
# s   = ctx.socket ZMQ::REP
# r   = ctx.socket ZMQ::REP
# rc  = s.setsockopt(ZMQ::SNDHWM)
# rc  = s.setsockopt(ZMQ::RCVHWM)
# print(s.bind(send_url))
# print(r.bind(receive_url))

message = 'Message:'

count = 3
while true
    sleep 1
    rc = rep_sock.send_string('Polo!')
    error_check(rc)
    # count = count + 1
    # print(message + count.to_s)
    # sent_msg = ZMQ::Message.new("#{message} #{count}")
    # received_msg = ZMQ::Message.new

    # print s.sendmsg(sent_msg)
    # print r.recvmsg(received_msg)

end