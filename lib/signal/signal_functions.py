import pdb
import json
import requests
import re
import sys
import regex
import time
try:
    from PIL import Image
except ImportError:
    import Image
import pytesseract

from decimal import *
from lib.detect import *
from lib.ocr import text_image_detect

class SignalFunction():

	def __init__(self, sc, tg, _zmq, database, signal):
		self._sc = sc
		self._tg = tg
		self._zmq = _zmq
		self._database = database
		self._signal = signal
		self._signal_image = False


	def _deEmojify(self, message):
		regrex_pattern = re.compile(pattern = "["
			u"\U0001F600-\U0001F64F"  # emoticons
			u"\U0001F300-\U0001F5FF"  # symbols & pictographs
			u"\U0001F680-\U0001F6FF"  # transport & map symbols
			u"\U0001F1E0-\U0001F1FF"  # flags (iOS)
							   "]+", flags = re.UNICODE)
		return regrex_pattern.sub(r'',message)

	def _get_message(self, chat_id):
		result = self._tg.get_chat_history(chat_id)
		result.wait()
		if result.error:
			print(f'Error Get Message: {result.error_info}')
		else:
			return result.update

	# pdb.set_trace()

	def _save_database(self, database, telegram_message_id=None, signal_name=None, telegram_result=None, chat_id=None):
		if telegram_message_id:
			database['telegram'][str(chat_id)].append({
				"message_id": telegram_message_id, "signal_name": signal_name, "message_text": telegram_result['messages'][0]['content']
			})
		with open("database.json", "w") as outfile:
			json.dump(database, outfile)

	def _check_and_create_database(self, chat_id, database):
		if not (str(chat_id) in database['telegram'].keys()):
			database['telegram'][str(chat_id)] = []
			self._save_database(database)

	def _get_track_price_metatrader(self, _symbol):
		response = None
		self._zmq.send_trackprices_request(symbols=[_symbol])
		time.sleep(1)
		self._zmq.send_hist_request(symbol=_symbol)
		time.sleep(1)
		while(response == None):
			response = self._zmq._get_response_()
		return response['_data'][-1]['close']

	def _calculete_loss_gain(self, enter_price, stop_price, market_price):
		decimal_market_price = abs((Decimal(str(market_price))).as_tuple().exponent)
		decimal_enter_price = abs((Decimal(enter_price)).as_tuple().exponent)
		if decimal_enter_price < decimal_market_price:
			enter_price = f'%.{decimal_market_price}f' % float(enter_price)
			stop_price = f'%.{decimal_market_price}f' % float(stop_price)
			return abs(int((float(stop_price) - float(enter_price)) * 10 ** decimal_market_price))
		else:
			return abs(int((float(stop_price) - float(enter_price)) * 10 ** decimal_enter_price))

	def prepare_signal(self):
		# chat_id = -1001287502434 #- technicalPips
		# chat_id = 60866983
		# chat_id = 487330707 #- Breno Perucchi
		# chat_id = -481414224 # RoboSignalGroup
		# chat_id = -1001389557656 #- technicalPips VIP
		
		signal_name = self._signal
		if 'technical' in signal_name:
			# check_chat_id = self._tg.call_method('checkChatInviteLink', params={'invite_link': 'https://t.me/joinchat/AAAAAFLS95gUnQM_N75uoA'})
			check_chat_id = self._tg.get_chat('-1001389557656')
			check_chat_id.wait()
			chat_id = check_chat_id.update['id']
		elif 'swing_trading' in signal_name:
			check_chat_id = self._tg.call_method('searchChatsOnServer',   params={'query': 'Swing Trading ViP', 'limit':10})
			check_chat_id.wait()
			chat_id = check_chat_id.update['chat_ids'][0]
		elif 'M15_Signals' in signal_name:
			# check_chat_id = self._tg.get_chat('-1001490464609')
			check_chat_id = self._tg.get_chat('-1001222448337')
			check_chat_id.wait()
			chat_id = check_chat_id.update['id']
			self._signal_image = True
		elif 'test' in signal_name:
			# signal_name = 'technical'
			# signal_name = 'swing_trading'
			signal_name = 'M15_Signals'
			self._signal_image = True
			check_chat_id = self._tg.call_method('searchChatsOnServer',   params={'query': 'RoboSignal', 'limit':10})
			check_chat_id.wait()
			chat_id = check_chat_id.update['chat_ids'][0]
		else:
			print('Error Signal Name')
			return 

		self._check_and_create_database(chat_id, self._database)
		telegram_result = self._get_message(chat_id)
		telegram_user = self._tg.get_chat(chat_id)
		telegram_user.wait()
		self._telegram_username = telegram_user.update['title']
		telegram_message_id = telegram_result['messages'][0]['id']

		if not any(d.get('message_id') == telegram_message_id for d in self._database['telegram'].get(str(chat_id), [] )):
			self._save_database(self._database, telegram_message_id, signal_name, telegram_result, chat_id)
			message = self._parse_message(telegram_result)

			if(('BUY' in message[0].upper() or "SELL" in message[0].upper()) and 'None' not in message[0].upper()):
				#Call Polymorphic Function
				# _my_trade = getattr(sys.modules[__name__], ('rules_of_signal_'+ signal_name.lower()))(telegram_message_id, message, telegram_username, chat_id)
				try:
					_my_trade = getattr(self, '_' + ('rules_of_signal_'+ signal_name.lower()))(telegram_message_id, message, chat_id)
				except Exception as e:
					print(f"Error Prepare Signal / Function {('rules_of_signal_'+ signal_name.lower())} / Exception: {e}")
					return
				self._create_metatrader_order(_my_trade, chat_id, message)

	def _parse_message(self, message):
		try:
			if self._signal_image and 'photo' in message['messages'][0]['content'].keys():
				if 'photo' in message['messages'][0]['content'].keys():
					remote_file_id = message['messages'][0]['content']['photo']['sizes'][0]['photo']['remote']['id']
				elif "image" in message['messages'][0]['content']['document']['mime_type']:
					remote_file_id = message['messages'][0]['content']['document']['thumbnail']['photo']['remote']['id']
				message =  message['messages'][0]['content']['caption']['text']
				symbol = self._detect_text_image(remote_file_id)
				# symbol = re.sub('[^a-zA-Z]+', '', symbol)
				message = F'{symbol} {message}'
			else:
				message = message['messages'][0]['content']['text']['text']
			message = self._deEmojify(message)
			message = re.split(r'\n', message)
			print('Telegram Message:', self._telegram_username, ' Text: ', message)
			return message
		except Exception as e:
			print(f'Error Parse Message: {message} exception: {e}')
			return ['']

	def _create_metatrader_order(self, _my_trade, chat_id, message):
		try:
			self._zmq.new_trade(_order=_my_trade)
			self._save_database_api(_my_trade, chat_id, message, self._telegram_username)
			print('Create Meta Trader Order: ', self._telegram_username, 'My_Trade: ', _my_trade)
		except: 
			e = sys.exc_info()[0]
			print(f"Error Create MetaTrader Order: {_my_trade} / Excpetion: {e}")
			return

	def _detect_text_image(self, remote_file_id, timer = 1):
		try:
			remote_file = self._tg.call_method('getRemoteFile', params={'remote_file_id': remote_file_id})
			time.sleep(timer)
			remote_file.update
			file_id = remote_file.update['id']
			file = self._tg.call_method('downloadFile', params={'file_id': file_id, 'priority': 1, 'offset':0, 'limit':10, 'synchronous':True})
			time.sleep(timer)
			path = file.update['local']['path']
			error = None
			message = text_image_detect(path)
			# message = detect_text(path)
			message = re.sub(" / ", "",  message).strip()
			print("Detect Text in Message :", message)
			return message
		except Exception as e:
			print(f"Detect Text Error / Remote File Id :{remote_file_id} / Exception :{e}")
			timer = timer + 0.5
			if timer < 2:
				self._detect_text_image(remote_file_id, timer)
			else:
				return 


	def _save_database_api(self, _my_trade, chat_id, message, telegram_username):
		response = None
		while(response == None):
			 response = self._zmq._get_response_()
		pload = {
			'provider': chat_id,
			'provider_name': telegram_username,
			'symbol':_my_trade['_symbol'],
			'action':response['_action'],
			'kind': _my_trade['_tid'],
			'price_request': _my_trade['_price'],
			'price_open': response.get('_open_price'),
			'stop_loss': response.get('_sl'),
			'take_profit_1': response.get('_tp'),
			'comment': _my_trade['_comment'],
			'magic':response.get('_magic'),
			'ticket':response.get('_ticket'),
			'open_at':response.get('_open_time'),
			'context': " ".join(message),
			'response':response.get('_response'),
			'response_value':response.get('response_value')
		 }
		r = requests.post('http://localhost/api/v1/signs',data = pload)
		print('Response API :', r.text)

	def _rules_of_signal_technical(self, telegram_message_id, message, chat_id):
		_my_trade = self._zmq.generate_default_order_dict()
		price_request = re.search(r"[\d]+[.,\d]+", message[1]).group(0)
		if 'BUY' in message[0]:
			_my_trade['_tid'] = 0
		elif 'SELL' in message[0]:
			_my_trade['_tid'] = 1
		_my_trade['_symbol'] = regex.search(r'([^\s]+)', message[0]).group(1)
		market_price = self._get_track_price_metatrader(_my_trade['_symbol'])
		
		_my_trade['_price'] = price_request
		_my_trade['_SL'] = self._calculete_loss_gain(price_request, re.search(r"[\d]+[.,\d]+", message[2]).group(0), market_price)
		_my_trade['_TP'] = self._calculete_loss_gain(price_request, re.search(r"[\d]+[.,\d]+", message[3]).group(0), market_price)
		_my_trade['_comment'] = self._telegram_username
		return _my_trade

	def _rules_of_signal_swing_trading(self, telegram_message_id, message, chat_id):
		_my_trade = self._zmq.generate_default_order_dict()
		price_request = regex.search(r'\@(.*?$)', message[0]).group(1).strip()
		if 'buy' in message[0]:
			_my_trade['_tid'] = 0
		elif 'sell' in message[0]:
			_my_trade['_tid'] = 1
		_my_trade['_symbol'] = regex.search(r'([^\s]+)', message[0]).group(1).upper()
		market_price = self._get_track_price_metatrader(_my_trade['_symbol'])

		_my_trade['_price'] = price_request
		_my_trade['_SL'] = self._calculete_loss_gain(price_request, regex.search(r'\Sl @(.*?$)',  message[1]).group(1).strip(), market_price)
		_my_trade['_TP'] = self._calculete_loss_gain(price_request, regex.search(r'\Tp1 @(.*?$)', message[2]).group(1).strip(), market_price)
		print(f"STOP LOSS: {_my_trade['_SL']} TAKE PROFIT: {_my_trade['_TP']}")
		_my_trade['_comment'] = self._telegram_username
		return _my_trade	

	def _rules_of_signal_m15_signals(self, telegram_message_id, message, chat_id):
		_my_trade = self._zmq.generate_default_order_dict()
		price_request = regex.search(r'\ (.*?$)', message[0]).group(1).split()[1]
		if 'BUY' in message[0]:
			_my_trade['_tid'] = 0
		elif 'SELL' in message[0]:
			_my_trade['_tid'] = 1
		_my_trade['_symbol'] = regex.search(r'([^\s]+)', message[0]).group(1)
		market_price = self._get_track_price_metatrader(_my_trade['_symbol'])
		
		_my_trade['_price'] = price_request
		_my_trade['_SL'] = self._calculete_loss_gain(price_request, re.sub("SL ", "", message[5]), market_price)
		_my_trade['_TP'] = self._calculete_loss_gain(price_request, re.sub("TP ", "", message[2]), market_price)
		print(f"STOP LOSS: {_my_trade['_SL']} TAKE PROFIT: {_my_trade['_TP']}")
		_my_trade['_comment'] = self._telegram_username
		return _my_trade