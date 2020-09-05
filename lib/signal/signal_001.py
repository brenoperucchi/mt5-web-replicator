import pdb
import sched, time
import re
import pdb
import os
import sys
import regex

from telegram_api.client import Telegram
from DWX_v2_0_1_RC8_001 import DwxZmqConnector
from decimal import *
from detect import *

messages_ids = {'technical': '0', 'swing_trading': '0', 'test':'0'}
account_type = 'micro'

_zmq = DwxZmqConnector(True)

tg = Telegram(
	api_id='980209',
	api_hash='03062326232cb23c6770e7a735c2dae2',
	phone='+5548984222627',
	database_encryption_key='changeme1234',
)
tg.login()

result_telegram = tg.call_method('searchPublicChat', params={'username': 'TechnicalPips'})
result_telegram.wait()

def deEmojify(message):
	regrex_pattern = re.compile(pattern = "["
		u"\U0001F600-\U0001F64F"  # emoticons
		u"\U0001F300-\U0001F5FF"  # symbols & pictographs
		u"\U0001F680-\U0001F6FF"  # transport & map symbols
		u"\U0001F1E0-\U0001F1FF"  # flags (iOS)
						   "]+", flags = re.UNICODE)
	return regrex_pattern.sub(r'',message)

def get_message(chat_id):
	result = tg.get_chat_history(chat_id)
	# result = tg.get_chat_history(487330707)
	result.wait()
	if result.error:
		print(f'error: {result.error_info}')
	else:
		return result.update

# pdb.set_trace()

s = sched.scheduler(time.time, time.sleep)

def signals(sc, messages_ids):
	prepare_signal(sc, messages_ids, 'technical')
	prepare_signal(sc, messages_ids, 'swing_trading')
	# prepare_signal(sc, messages_ids, 'test')
	s.enter(3, 1, signals, (sc,messages_ids))

def calculete_loss_gain(enter_price, stop_price):
	decimal = abs((Decimal(enter_price)).as_tuple().exponent)
	if account_type == "micro" and decimal == 4:
		return int(abs(float(stop_price) * (10 ** decimal) - float(enter_price) * (10 ** decimal))) * 10
	else:
		return int(abs(float(stop_price) * (10 ** decimal) - float(enter_price) * (10 ** decimal)))

def prepare_signal(sc, messages_ids, signal):
	# chat_id = -1001287502434 #- technicalPips
	# EURUSD BUY # Price:1.18600 # Stop:1.17100 # TP:1.18000

	# chat_id = 60866983
	# chat_id = 487330707 #- Breno Perucchi
	# chat_id = -481414224 # RoboSignalGroup
	# chat_id = -1001389557656 #- technicalPips VIP
	
	signal_name = signal
	if 'technical' in signal_name:
		# check_chat_id = tg.call_method('checkChatInviteLink', params={'invite_link': 'https://t.me/joinchat/AAAAAFLS95gUnQM_N75uoA'})
		check_chat_id = tg.get_chat('-1001389557656')
		check_chat_id.wait()
		chat_id = check_chat_id.update['id']
	elif 'swing_trading' in signal_name:
		check_chat_id = tg.call_method('searchChatsOnServer',   params={'query': 'Swing Trading ViP', 'limit':10})
		check_chat_id.wait()
		chat_id = check_chat_id.update['chat_ids'][0]
	elif 'test' in signal_name:
		signal_name = 'technical'
		# signal_name = 'swing_trading'
		check_chat_id = tg.call_method('searchChatsOnServer',   params={'query': 'RoboSignal', 'limit':10})
		check_chat_id.wait()
		chat_id = check_chat_id.update['chat_ids'][0]
	else:
		print('Error Signal Name')
		return

	telegram_result = get_message(chat_id)
	telegram_user = tg.get_chat(chat_id)
	telegram_user.wait()

	id_telegram_message = telegram_result['messages'][0]['id']


	if 'text' in telegram_result['messages'][0]['content'].keys(): 
		message = telegram_result['messages'][0]['content']['text']['text']
		message = deEmojify(message)
		message = re.split(r'\n', message)
		telegram_username = telegram_user.update['title']
		print(telegram_username, ' Text:', message)
		
		if(messages_ids[signal]!= id_telegram_message) and ('BUY' in message[0].upper() or "SELL" in message[0].upper()):
			print('Text:', message, 'Telegram:', id_telegram_message)
	
			#Call Polymorphic Function
			getattr(sys.modules[__name__], ('rules_of_signal_'+ signal_name.lower()))(id_telegram_message, message, telegram_username)
	# elif "image" in telegram_result['messages'][0]['content']['document']['mime_type']:
	# 	remote_file_id = telegram_result['messages'][0]['content']['document']['thumbnail']['photo']['remote']['id']
	# 	remote_file = tg.call_method('getRemoteFile', params={'remote_file_id': remote_file_id})
	# 	remote_file.wait()
	# 	remote_file.update
	# 	file_id = remote_file.update['id']
	# 	file = tg.call_method('downloadFile', params={'file_id': file_id, 'priority': 1, 'offset':0, 'limit':10, 'synchronous':True})
	# 	path = file.update['local']['path']
	# 	message = detect_text(path)



	messages_ids[signal] = id_telegram_message

def rules_of_signal_technical(id_telegram_message, message, telegram_username):
	_my_trade = _zmq._generate_default_order_dict()
	if 'BUY' in message[0]:
		_my_trade['_type'] = 0
		_my_trade['_symbol'] = regex.search(r'([^\s]+)', message[0]).group(1)
	elif 'SELL' in message[0]:
		_my_trade['_type'] = 1
		_my_trade['_symbol'] = regex.search(r'([^\s]+)', message[0]).group(1)
	
	_my_trade['_SL'] = calculete_loss_gain(re.sub("Price:", "", message[1]), re.sub("Stop:", "", message[2]))
	_my_trade['_TP'] = calculete_loss_gain(re.sub("Price:", "", message[1]), re.sub("TP:",   "", message[3]))
	_my_trade['_comment'] = telegram_username
	_zmq._DWX_MTX_NEW_TRADE_(_order=_my_trade)

def rules_of_signal_swing_trading(id_telegram_message, message, telegram_username):
	_my_trade = _zmq._generate_default_order_dict()
	if 'buy' in message[0]:
		_my_trade['_type'] = 0
		# _my_trade['_price'] = regex.search(r'\@(.*?$)', message[0]).group(1).strip()
	elif 'sell' in message[0]:
		_my_trade['_type'] = 1
		# _my_trade['_price'] = regex.search(r'\@(.*?$)', message[0]).group(1).strip()
	
	_my_trade['_symbol'] = regex.search(r'([^\s]+)', message[0]).group(1).upper()
	_my_trade['_SL'] = calculete_loss_gain(regex.search(r'\@(.*?$)', message[0]).group(1).strip(), regex.search(r'\Sl @(.*?$)',  message[1]).group(1).strip())
	_my_trade['_TP'] = calculete_loss_gain(regex.search(r'\@(.*?$)', message[0]).group(1).strip(), regex.search(r'\Tp1 @(.*?$)', message[2]).group(1).strip())
	_my_trade['_comment'] = telegram_username
	_zmq._DWX_MTX_NEW_TRADE_(_order=_my_trade)		

s.enter(3, 1, signals, (s,messages_ids))
s.run()