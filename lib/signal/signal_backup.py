import pdb
import sched, time
import re
import pdb
import os
import sys
import regex
from decimal import *
sys.path.append('/Users/brenoperucchi/Devs/telegram/lib/dwyte/v2.0.1b/python/api/dwx/dwx/')


from telegram_api.client import Telegram
from client import DwxZmqConnector


_zmq = DwxZmqConnector()
messages_ids = {'signal_technical': '0', 'swing_trading': '0'}

tg = Telegram(
	api_id='980209',
	api_hash='03062326232cb23c6770e7a735c2dae2',
	phone='+5548984222627',
	database_encryption_key='changeme1234',
)
tg.login()

# result2 = tg.call_method('searchChatsOnServer', params={'query': 'TechnicalPips', 'limit':10})
# tg.call_method('getUser', params={'user_id': 60866983})
# 1001287502434
result_telegram = tg.call_method('searchPublicChat', params={'username': 'TechnicalPips'})
result_telegram.wait()
# telegram_user['id'] = result_telegram.update['id']
# telegram_user['name'] = result_telegram.update['title']
# print('Id User:', telegram_user['id'], 'Name:', telegram_user['name'])
# telegram_user = tg.call_method('getUser', params={'user_id': chat_id})
def deEmojify(text):


	regrex_pattern = re.compile(pattern = "["
		u"\U0001F600-\U0001F64F"  # emoticons
		u"\U0001F300-\U0001F5FF"  # symbols & pictographsz
		u"\U0001F680-\U0001F6FF"  # transport & map symbols
		u"\U0001F1E0-\U0001F1FF"  # flags (iOS)
						   "]+", flags = re.UNICODE)
	return regrex_pattern.sub(r'',text)

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
	signal_technical(sc, messages_ids)
	swing_trading(sc, messages_ids)
	s.enter(3, 1, signals, (sc,messages_ids))

def calculete_loss_gain(enter_price, stop_price):
	pdb.set_trace()
	decimal = abs((Decimal(enter_price)).as_tuple().exponent)
	return int(abs(float(stop_price) * (10 ** decimal) - float(enter_price) * (10 ** decimal)))

def signal_technical(sc, messages_ids):
	# EURUSD BUY📈
	# Price:1.18600
	# Stop:1.17100
	# TP:1.18000

	# chat_id = -1001287502434 #- technicalPips
	

	# chat_id = 60866983
	# chat_id = 487330707 #- Breno Perucchi
	# chat_id = -481414224 # RoboSignalGroup

	# chat_id = -1001389557656 #- technicalPips VIP
	check_chat_id = tg.call_method('checkChatInviteLink', params={'invite_link': 'https://t.me/joinchat/AAAAAFLS95gUnQM_N75uoA'})
	check_chat_id.wait()
		

	telegram_result = get_message(chat_id)
	telegram_user = tg.get_chat(chat_id)
	telegram_user.wait()

	id_telegram_message = telegram_result['messages'][0]['id']
	
	if 'text' in telegram_result['messages'][0]['content'].keys(): 
		text = telegram_result['messages'][0]['content']['text']['text']
		text = deEmojify(text)
		text = re.split(r'\n', text)
		print('User:', telegram_user.update['title'], 'Text:', text)

		_my_trade = _zmq._generate_default_order_dict()

		if(messages_ids['signal_technical']!= id_telegram_message) and ('BUY' in text[0] or "SELL" in text[0]):
			print('Text:', text, 'Telegram:', id_telegram_message)

			if 'BUY' in text[0]:
				_my_trade['_type'] = 0
				_my_trade['_symbol'] = text[0].replace('BUY', '').strip()
			elif 'SELL' in text[0]:
				_my_trade['_type'] = 1
				_my_trade['_symbol'] = text[0].replace('SELL', '').strip()
			
			# pdb.set_trace()
			_my_trade['_SL'] = calculete_loss_gain(re.sub("Price:", "", text[1]), re.sub("Stop:", "", text[2]))
			_my_trade['_TP'] = calculete_loss_gain(re.sub("Price:", "", text[1]), re.sub("TP:",   "", text[3]))
			_my_trade['_comment'] = telegram_user.update['title']
			_zmq._DWX_MTX_NEW_TRADE_(_order=_my_trade)
	messages_ids['signal_technical'] = id_telegram_message
	s.enter(3, 1, signal_technical, (sc, messages_ids))


def swing_trading(sc, messages_ids):
	# GbpJpy sell now @ 138.80 # Sl @ 140.00 # Tp1 @ 138.00 # Tp2 @ 136.80
	# chat_id = -1001238380473 # Not VIP
	# chat_id = -1001159029077 # VIP
	# chat_id = -481414224 # RoboSignalGroup
	# check_chat_id = tg.call_method('searchChatsOnServer',   params={'query': 'Swing Trading ViP', 'limit':10})
	query_name = 'RoboSignal'
	check_chat_id = tg.call_method('searchChatsOnServer',   params={'query': query_name, 'limit':10})
	check_chat_id.wait()
	chat_id = check_chat_id.update['chat_ids'][0]

	telegram_result = get_message(chat_id)
	telegram_user = tg.get_chat(chat_id)
	telegram_user.wait()

	id_telegram_message = telegram_result['messages'][0]['id']

	if 'text' in telegram_result['messages'][0]['content'].keys(): 
		text = telegram_result['messages'][0]['content']['text']['text']
		text = deEmojify(text)
		text = re.split(r'\n', text)
		print('User:', telegram_user.update['title'], 'Text:', text)

		_my_trade = _zmq._generate_default_order_dict()

		if(messages_ids['swing_trading']!= id_telegram_message) and ('buy' in text[0] or "sell" in text[0]):
			print('Text:', text, 'Telegram:', id_telegram_message)
			_my_trade['_symbol'] = text[0][0:6].upper() 
			if 'buy' in text[0]:
				_my_trade['_type'] = 0
			elif 'sell' in text[0]:
				_my_trade['_type'] = 1
			
			_my_trade['_SL'] = calculete_loss_gain(regex.search(r'\@(.*?$)', text[0]).group(1).strip(), regex.search(r'\Sl @(.*?$)',  text[1]).group(1).strip())
			_my_trade['_TP'] = calculete_loss_gain(regex.search(r'\@(.*?$)', text[0]).group(1).strip(), regex.search(r'\Tp1 @(.*?$)', text[2]).group(1).strip())
			_my_trade['_comment'] = telegram_user.update['title']
			_zmq._DWX_MTX_NEW_TRADE_(_order=_my_trade)
	messages_ids['swing_trading'] = id_telegram_message
	s.enter(3, 1, swing_trading, (sc, messages_ids))

		
s.enter(3, 1, signals, (s,messages_ids))
s.run()