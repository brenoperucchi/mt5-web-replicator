# import os
# import zmq

# def main():

#     try:
#         context = zmq.Context(1)
#         # Socket facing clients
#         frontend = context.socket(zmq.PULL)
#         frontend.bind("tcp://*:5559")
        
#         # Socket facing services
#         backend = context.socket(zmq.PUSH)
#         backend.bind("tcp://*:5560")

#         zmq.device(zmq.STREAMER, frontend, backend)
#     except Exception as e:
#         print(e.message, e.args)
#         print("bringing down zmq device")
#     finally:
#         pass
#         frontend.close()
#         backend.close()
#         context.term()

# if __name__ == "__main__":
#     main()

import os
import zmq

def main():

    try:
        context = zmq.Context(1)
        # Socket facing clients
        frontend = context.socket(zmq.SUB)
        frontend.bind("tcp://*:5559")
        
        frontend.setsockopt_string(zmq.SUBSCRIBE, "")
        
        # Socket facing services
        backend = context.socket(zmq.PUB)
        backend.bind("tcp://*:5560")

        zmq.device(zmq.FORWARDER, frontend, backend)
    except Exception as e:
        print(e.message, e.args)
        print("bringing down zmq device")
    finally:
        pass
        frontend.close()
        backend.close()
        context.term()

if __name__ == "__main__":
    main()
