import argparse
import pdb
import sched, time, datetime
import json

from telegram.client import Telegram
from signal_functions_004 import SignalFunction


ap = argparse.ArgumentParser()
ap.add_argument("-e", "--environment", type=str, required=True, help="Environment Choice: development / production / local")
args = vars(ap.parse_args())

if args['environment'].lower() == 'development':
	API_URL = "http://benincasouza.tplinkdns.com:8080/api/v1/signs"
	META_HOST = 'metaserver.imentore.com.br'
	ENVIRONMENT = 'development'
	SIGNALS = ['test']
	META_PORTS = [32768, 32769, 32770]
	API_ID = '1478090'
	API_HASH = '04c2afe8f6dd37450e69a9ece6dce187'
	PHONE_NUMBER = '+5548991268808'
	DATABASE_ENCRYPT = 'changeme1234'
	LIBRARY_PATH = '/home/bperucchi/app/telegram/lib/signal/lib/libtdjson_64.so'
	DATABASE_PATH = '/home/bperucchi/app/telegram/lib/signal/database.json'

elif args['environment'].lower() == 'local':
	API_URL = "http://localhost/api/v1/signs"
	META_HOST = '192.168.1.245'
	ENVIRONMENT = 'local'
	META_PORTS = [32768, 32769, 32770]
	SIGNALS = ['test']
	API_ID = '1478090'
	API_HASH = '04c2afe8f6dd37450e69a9ece6dce187'
	PHONE_NUMBER = '+5548991268808'
	DATABASE_ENCRYPT = 'changeme1234'
	LIBRARY_PATH = '/Users/brenoperucchi/env/lib/python3.8/site-packages/telegram_api/lib/darwin/libtdjson.dylib'
	DATABASE_PATH = "/Users/brenoperucchi/Devs/telegram/lib/signal/database.json"

elif args['environment'].lower() == 'production':
	API_URL = "http://benincasouza.tplinkdns.com:8080/api/v1/signs"
	META_HOST = 'metaserver.imentore.com.br'
	ENVIRONMENT = 'production'
	# signals = ['technical', 'swing_trading', 'M15_Signals']
	SIGNALS = ['swing_trading', 'M15_Signals']
	META_PORTS = [32768, 32769, 32770]
	API_ID = '980209'
	API_HASH = '03062326232cb23c6770e7a735c2dae2'
	PHONE_NUMBER = '+5548984222627'
	DATABASE_ENCRYPT = 'changeme1234'
	LIBRARY_PATH = '/home/bperucchi/app/telegram/lib/signal/lib/libtdjson_64.so'
	DATABASE_PATH = '/home/bperucchi/app/telegram/lib/signal/database.json'


with open(DATABASE_PATH, "r") as json_file:
	database = json.load(json_file)

tg = Telegram(api_id=API_ID, api_hash=API_HASH, phone=PHONE_NUMBER, database_encryption_key=DATABASE_ENCRYPT, library_path= LIBRARY_PATH)


def signals(sc):
	for i in range(len(SIGNALS)):
		tg.login()
		SignalFunction(sc, tg, database, SIGNALS[i], API_URL, ENVIRONMENT, META_HOST, META_PORTS).prepare_signal()
	s.enter(3, 1, signals, (sc,))

s = sched.scheduler(time.time, time.sleep)
s.enter(3, 1, signals, (s,))
s.run()	