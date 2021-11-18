require 'ffi-rzmq'

class MetaZmq
	def initialize(args)
		ctx = ZMQ::Context.new
		@zmq_pull   = ctx.socket ZMQ::PULL
		@zmq_pull.connect("tcp://0.0.0.0:5560")
		
		# @zmq_pull.setsockopt(ZMQ::SUBSCRIBE, "")

		@zmq_push  = ctx.socket ZMQ::PUSH
		@zmq_push.connect("tcp://0.0.0.0:5559")
		
	end


	def trade
		order = "45103446 OPEN|EURUSD|000001|OP_BUY|0.0|0.0|0.1|0.0|0.0"
		# order = ZMQ::Message.new(order)
		msg = @zmq_push.send_string order, 0
		print "Order: #{msg}"
		return
	end	



		# {'_action': 'OPEN',
  #                 '_type': 0,
  #                 '_symbol': 'EURUSD',
  #                 '_price': 0.0,
  #                 '_SL': 500, # SL/TP in POINTS, not pips.
  #                 '_TP': 500,
  #                 '_comment': self._ClientID,
  #                 '_lots': 0.01,
  #                 '_magic': 123456,
  #                 '_ticket': 0}
	
	def response
		# @zmq_pull.recv_string msg = '', 0 
		# print msg
		return true
	end
end