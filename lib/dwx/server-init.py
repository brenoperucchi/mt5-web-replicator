import os
import pdb
import time
from dwx_connector import DWX_ZeroMQ_Connector

zmq = DWX_ZeroMQ_Connector()

message = zmq._PULL_SOCKET.recv_string()
print("Receive Client: ", message)
order = zmq._generate_default_order_dict()
zmq._DWX_MTX_NEW_TRADE_(order)

# time.sleep (1)  
# zmq._PUSH_SOCKET.send_string("Server Message")
#  Wait for next request from client
# message = zmq._PULL_SOCKET.recv_string()
# print("Received request: ", message)
# zmq._PULL_SOCKET.send_string("teste server")