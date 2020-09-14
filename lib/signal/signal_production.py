import pdb
import sched, time
import json

from telegram_api.client import Telegram
from functions.signal_functions_004 import SignalFunction
from lib.DWX_v2_0_1_RC8_004 import DWX_ZeroMQ_Connector

with open("database.json", "r") as json_file:
	database = json.load(json_file)

_zmq = DWX_ZeroMQ_Connector(verbose=False)
METATRADER_URL = "http://benincasouza.tplinkdns.com:8080/api/v1/signs"
ENVIRONMENT = 'production'

tg = Telegram(
	api_id='980209',
	api_hash='03062326232cb23c6770e7a735c2dae2',
	phone='+5548984222627',
	database_encryption_key='changeme1234',
	# library_path='/home/bperucchi/app/telegram/lib/signal/lib/libtdjson_64.so'
)

tg.login()

def signals(sc):
	# SignalFunction(sc, tg, _zmq, database, 'technical', METATRADER_URL, ENVIRONMENT).prepare_signal()
	SignalFunction(sc, tg, _zmq, database, 'swing_trading', METATRADER_URL, ENVIRONMENT).prepare_signal()
	SignalFunction(sc, tg, _zmq, database, 'M15_Signals', METATRADER_URL, ENVIRONMENT).prepare_signal()
	# SignalFunction(sc, tg, _zmq, database, 'test', METATRADER_URL, ENVIRONMENT).prepare_signal()
	s.enter(3, 1, signals, (sc,))

s = sched.scheduler(time.time, time.sleep)
s.enter(3, 1, signals, (s,))
s.run()	