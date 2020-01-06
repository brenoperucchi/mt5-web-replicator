#!/usr/bin/env ruby

require 'rubygems' # or use Bundler.setup
require 'eventmachine'
require 'ffi-rzmq'

class EchoServer < EM::Connection
  def receive_data(data)
    # send_data(data)

    link = "tcp://192.168.1.245:5555"

    begin
      ctx = ZMQ::Context.new
      s2 = ctx.socket(ZMQ::SUB)
    rescue ContextError => e
      STDERR.puts "Failed to allocate context or socket!"
      raise
    end

    assert(s2.setsockopt(ZMQ::SUBSCRIBE, '')) # receive all
    assert(s2.connect(link))
    sleep 1
    puts "receiving"
    received_msg = ZMQ::Message.new
    s2.recvmsg(received_msg)
    puts received_msg.copy_out_string
    assert(s2.close)
    ctx.terminate
  end
end

EventMachine.run do
  # hit Control + C to stop
  Signal.trap("INT")  { EventMachine.stop }
  Signal.trap("TERM") { EventMachine.stop }

  EventMachine.start_server("0.0.0.0", 10000, EchoServer)
end