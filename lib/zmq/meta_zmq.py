import zmq
import pdb
import random
import sys
import time
from time import sleep
from pandas import DataFrame, Timestamp
from threading import Thread

# 30-07-2019 10:58 CEST
from zmq.utils.monitor import recv_monitor_message

class MetaZmq():
	def __init__(self):
		self._context = zmq.Context()
		self._push_socket = self._context.socket(zmq.PUB)
		# push_socket.setsockopt(zmq.SNDHWM, 1)        
		self._push_socket.connect("tcp://localhost:5559")

	def serializer_order(self, attributes, action):
		_msg = "{} {} {}|{}|{}|{}|{}|{}|{}|{}|{}|{}".format(attributes['trace_id'], 'CLIENT', 
														 action, attributes['instrument'], attributes['transaction_id'],
														 attributes['ordertype'], attributes['openprice'], 0, 
														 attributes['volume'], attributes['stoploss'], 
														 attributes['takeprofit'], attributes['magic_number'])
		return _msg

	def _trade(self, attributes):
		# order = "45103446 OPEN|EURUSD|000001|OP_BUY|0.0|0.0|0.1|0.0|0.0"
		# order = "TRADE|OPEN|1|EURUSD|0|50|50|R-to-MetaTrader4|0.01|00001|12345678"
		order = self.serializer_order(attributes, "OPEN")
		# push_socket.send_string(order, zmq.DONTWAIT)
		time.sleep(1)
		print(order)
		self._push_socket.send_string(order)
		self._push_socket.disconnect("tcp://localhost:5559")
		self._push_socket.close()
		self._context.destroy()

	def _trade_modify(self, attributes):
		attributes = self.serializer_order(attributes, "MODIFY")
		time.sleep(1)
		print(attributes)
		self._push_socket.send_string(attributes)
		self._push_socket.disconnect("tcp://localhost:5559")
		self._push_socket.close()
		self._context.destroy()

	def _trade_close(self, attributes):
		attributes = self.serializer_order(attributes, "CLOSED")
		time.sleep(1)
		print(attributes)
		self._push_socket.send_string(attributes)
		self._push_socket.disconnect("tcp://localhost:5559")
		self._context.destroy()		

# def normatize_ordertype(self, order_type):
# 	if order_type == 'ORDER_TYPE_BUY':
# 		return "0"
# 	elif order_type == 'ORDER_TYPE_SELL':
# 		return '1'
# 	elif order_type == 'ORDER_TYPE_BUY_LIMIT':
# 		return '2'
# 	elif order_type == 'ORDER_TYPE_SELL_LIMIT':
# 		return '3'
# 	elif order_type == 'ORDER_TYPE_BUY_STOP':
# 		return '4'
# 	elif order_type == 'ORDER_TYPE_SELL_STOP':
# 		return '5'
# 	# if order_type == 'ORDER_TYPE_BUY':
# 	# 	return "0"
# 	# elif order_type == 'ORDER_TYPE_SELL':
# 	# 	return '1'
# 	# elif order_type == 'ORDER_TYPE_BUY_LIMIT':
# 	# 	return '2'
# 	# elif order_type == 'ORDER_TYPE_SELL_LIMIT':
# 	# 	return '3'
# 	# elif order_type == 'ORDER_TYPE_BUY_STOP':
# 	# 	return '4'
# 	# elif order_type == 'ORDER_TYPE_SELL_STOP':
# 	# 	return '5'



# def _login_check(self, attributes={}):
# 	_msg = "{}|{}".format(attributes['account_login'], attributes['login_check'])
# 	print(_msg)
# 	self._push_socket.send_string(_msg)
# 	time.sleep(2)
# 	self._push_socket.disconnect("tcp://localhost:5559")
# 	self.close()


# pull_socket = context.socket(zmq.PULL)	
# pull_socket.connect("tcp://127.0.0.1:5560")
# # pull_socket.setsockopt(zmq.LINGER, 0)
# pull_socket.setsockopt(zmq.RCVHWM, 1)
# msg = pull_socket.recv()
# print(msg)
# pdb.set_trace()
# poller = zmq.Poller()
# poller.register(pull_socket, zmq.POLLIN)		
# socks = dict(poller.poll(1000))
# if socks.get(pull_socket) == zmq.POLLIN:
# 	message = pull_socket.recv_string(zmq.NOBLOCK)
# 	print(message)
# 	if("ERROR" in message):
# 		return message

# # if socks:
# # 	if socks.get(pull_socket) == zmq.POLLIN:
# sleep(3)
# msg = pull_socket.recv(zmq.NOBLOCK)
# print(msg)
# return msg
# # pdb.set_trace()
# # else:
# # 	print("error: message timeout")
# # 	return "error MetaZmq"

# order = '%s|%s|%s|%s|%s|%s|%s|%s|.'%('TRADE', 'OPEN', order.instrument, normatize_ordertype(type=order.ordertype), order.stoploss, order.take_profit, order.comment, order.volume)	
# _msg = "{}|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}".format('TRADE', action, self.normatize_ordertype(attributes['ordertype']),
# 												 attributes['instrument'], attributes['openprice'],
# 												 attributes['stoploss'], attributes['takeprofit'], attributes['comment'], 
# 												 attributes['volume'], attributes['magic'], attributes['ticket'])