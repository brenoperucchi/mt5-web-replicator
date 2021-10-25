import zmq
import time
import sys
import pdb


port = "5555"
if len(sys.argv) > 1:
    port =  sys.argv[1]
    int(port)
context = zmq.Context()
sender = context.socket(zmq.PUSH)
sender.bind("tcp://192.168.1.240:5550")

receiver = context.socket(zmq.PULL)
receiver.bind("tcp://192.168.1.240:5551")

while True:
    #  Wait for next request from client
    message = receiver.recv_string()
    # pdb.set_trace()
    print("Receive Client: ", message)
    time.sleep (1)  
    sender.send_string("Server Message")