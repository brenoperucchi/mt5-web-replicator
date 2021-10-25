import os
import pdb
import socket
import socketserver
from datetime import datetime, timedelta 


class socketserver:
    def __init__(self, address = '', port = 8700):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.address = address
        self.port = port
        self.sock.bind((self.address, self.port))
        self.cummdata = ''
    def waitforconnection(self):
        self.sock.listen(1)
        self.conn, self.addr = self.sock.accept()
        print('connected to', self.addr)
        return 1

    def recvmsg(self):
        self.cummdata = ''
        while True:
            data = self.conn.recv(1024)
            # data = self.conn.recv(10000)
            print('received data1 : ',data.decode("utf16"));
            self.cummdata+=data.decode("utf16")
            if not data:
                break    

            self.conn.send(bytes(self.cummdata,"utf-8")) # loop back test
            self.conn.send(b'Client DateTime')

            return self.cummdata
   
    def __del__(self):
        print('sock close')
        self.sock.close()

#####################################################

serv = socketserver('192.168.1.240', 8701)
serv.waitforconnection()

while True: 
    msg = serv.recvmsg()
    print('received data : ',msg);