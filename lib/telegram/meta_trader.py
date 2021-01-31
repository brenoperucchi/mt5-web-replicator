import requests
import pdb
import numpy as np
import pandas as pd
import configparser
import pytz

from datetime import datetime, timedelta 
from pytrader.Pytrader_API_V1_04 import Pytrader_API

class MetaTrader():
	def __init__(self, meta_host, meta_port, symbol_list):
		self.meta_host = meta_host
		self.meta_port = int(meta_port)
		self.symbol_list = symbol_list
		self.meta = self.connect()

	def config_instruments(self, config, section):
	    dict1 = {}
	    options = config.options(section)
	    for option in options:
	        try:
	            option = option.upper()
	            dict1[option] = config.get(section, option)
	            if dict1[option] == -1:
	                print("skip: %s" % option)
	        except BaseException:
	            print("exception on %s!" % option)
	            dict1[option] = None
	    return dict1

	def connect(self):
		meta = Pytrader_API()
		# Read in config
		# CONFIG_FILE = "/Users/brenoperucchi/Devs/signalforex/lib/telegram/pytrader/instrument.conf"
		# config = configparser.ConfigParser()
		# config.read(CONFIG_FILE)

		# brokerInstrumentsLookup = self.config_instruments(config, "ICMarkets")
		Connected = meta.Connect(
			server=self.meta_host,
			port=self.meta_port,
			instrument_lookup=self.symbol_list)
		meta.debug = False

		IsAlive = meta.connected
		# print(IsAlive)

		CheckAlive = meta.Check_connection()

		meta.Set_timeout(timeout_in_seconds=120)

		ServerTime = meta.Get_broker_server_time()

		return meta

	def order_send(self, meta_attributes):
		print('MY_Trade: ', meta_attributes)
		
		MT = self.meta

		ticket = self.meta.Open_order(**meta_attributes)

		if(ticket == -1):
			print(MT.order_error)
			print(MT.order_return_message)
		else:
			print(ticket)	

		trades = self.meta.Get_all_open_positions()
		meta_attributes['response_value'] = self.meta.order_error
		meta_attributes['response']	    = self.meta.order_return_message
		if (ticket == -1):  # opening order failed
			meta_attributes['open_price'] = None
			meta_attributes['open_time'] = None
			meta_attributes['ticket'] = None
			meta_attributes['account_login'] = None
		else:
			meta_attributes['ticket'] = ticket
			for num in trades.index:
				if trades['ticket'][num] == ticket:
					meta_attributes['open_price'] = trades['open_price'][num]
					meta_attributes['open_time'] = datetime.fromtimestamp(trades['open_time'][num]).strftime('%Y-%m-%d %H:%M:%S')
		return meta_attributes

	def get_closed_positions(self):
		timezone = pytz.timezone("Etc/UTC")
		account_login = self.meta.Get_static_account_info()['login']
		trades = self.meta.Get_all_closed_positions(date_from=datetime(2021, 1, 1, tzinfo=timezone), date_to=datetime.now() + timedelta(hours=5))		
		return trades