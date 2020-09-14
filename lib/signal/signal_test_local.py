import pdb
import sched, time
import json

from telegram_api.client import Telegram
from functions.signal_functions_test import SignalFunction
from lib.DWX_v2_0_1_RC8_Test import DWX_ZeroMQ_Connector

with open("database.json", "r") as json_file:
	database = json.load(json_file)

_zmq = DWX_ZeroMQ_Connector()
METATRADER_URL = "http://localhost/api/v1/signs"
ENVIRONMENT = 'development'

tg = Telegram(
	api_id='1478090',
	api_hash='04c2afe8f6dd37450e69a9ece6dce187',
	phone='+5548991268808',
	database_encryption_key='changeme1234',
	# library_path='/home/bperucchi/app/telegram/lib/signal/lib/libtdjson_64.so'
)

tg.login()

def signals(sc):
	# SignalFunction(sc, tg, _zmq, database, 'technical', METATRADER_URL, ENVIRONMENT).prepare_signal()
	# SignalFunction(sc, tg, _zmq, database, 'swing_trading', METATRADER_URL, ENVIRONMENT).prepare_signal()
	# SignalFunction(sc, tg, _zmq, database, 'M15_Signals', METATRADER_URL, ENVIRONMENT).prepare_signal()
	SignalFunction(sc, tg, _zmq, database, 'test', METATRADER_URL, ENVIRONMENT).prepare_signal()
	s.enter(3, 1, signals, (sc,))

s = sched.scheduler(time.time, time.sleep)
s.enter(3, 1, signals, (s,))
s.run()	