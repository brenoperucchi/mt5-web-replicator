import pdb
import sched, time
import json

from signal_functions import SignalFunction
from telegram_api.client import Telegram
from lib.DWX_v2_0_1_RC8_003 import DWX_ZeroMQ_Connector

with open("database.json", "r") as json_file:
	database = json.load(json_file)

_zmq = DWX_ZeroMQ_Connector(verbose=False)

tg = Telegram(
	api_id='980209',
	api_hash='03062326232cb23c6770e7a735c2dae2',
	phone='+5548984222627',
	database_encryption_key='changeme1234',
)

tg.login()

def signals(sc):
	SignalFunction(sc, tg, _zmq, database, 'technical').prepare_signal()
	SignalFunction(sc, tg, _zmq, database, 'swing_trading').prepare_signal()
	SignalFunction(sc, tg, _zmq, database, 'M15_Signals').prepare_signal()
	# SignalFunction(sc, tg, _zmq, database, 'test').prepare_signal()
	s.enter(3, 1, signals, (sc,))

s = sched.scheduler(time.time, time.sleep)
s.enter(3, 1, signals, (s,))
s.run()	