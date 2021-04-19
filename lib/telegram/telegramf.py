import pdb
import json
import re
import sys
import time, datetime
import os

# from signals_api import SignalApi
# from signals_meta import SignalsMeta
from telegram.client import Telegram
dir_path = os.path.dirname(os.path.realpath(__file__))

class Telegramf():
	def __init__(self, config={}):
		self._config = {
			'HOSTNAME': "localhost:80",
			'ENVIRONMENT': 'local',
			'API_ID': '980209',
			'API_HASH': '03062326232cb23c6770e7a735c2dae2',
			'PHONE_NUMBER': '+5548984222627',
			'DATABASE_ENCRYPT': 'changeme1234',
			'LIBRARY_PATH': f'{dir_path}/tdlib/libtdjson.dylib'
		}
		
	def connect(self):
		self._tg = Telegram(api_id=self._config['API_ID'], api_hash=self._config['API_HASH'], phone=self._config['PHONE_NUMBER'], database_encryption_key=self._config['DATABASE_ENCRYPT'], library_path=self._config['LIBRARY_PATH'])		
		self._tg.login()

	def disconnect(self):
		self._tg.stop()

	def query_message(self, trace):
		if trace:
			signal_name = trace.name()
			self._signal_image = trace.telegram_image()
			if trace.telegram_option() == 'query_name':
				telegram_query = self._tg.call_method('searchChatsOnServer',   params={'query': trace.name(), 'limit':10})
				telegram_query.wait()
				get_chat = self._tg.get_chat(telegram_query.update['chat_ids'][0])

			if trace.telegram_option() == 'query_name_id':
				telegram_query = self._tg.call_method('searchChatsOnServer',   params={'query': trace.name_id(), 'limit':10})
				telegram_query.wait()
				get_chat = self._tg.get_chat(trace.name_id())
			get_chat.wait()
			get_chat.update
			get_chat.wait()
			if 	get_chat.error:
				return dict(chat_history= None, error=get_chat.error, error_info=get_chat.error_info)
			else:
				chat_id = get_chat.update['id']
				# self._signal_image = True #######################################################
				# chat_history, error, error_info = self._get_chat_history(get_chat)
				chat_history, error, error_info = self._get_chat_history(get_chat)
				# print(f'### {trace.name()} ## {trace.name_id()} #####')
				return dict(chat_history= chat_history, error=error, error_info=error_info)

	
	def _get_photo_path(self, message, timer=0.5):
		try:
			if self._signal_image and self._signal_image_check:
				if 'photo' in message['messages'][0]['content'].keys():
					remote_file_id = message['messages'][0]['content']['photo']['sizes'][0]['photo']['remote']['id']
				elif "image" in message['messages'][0]['content']['document']['mime_type']:
					remote_file_id = message['messages'][0]['content']['document']['thumbnail']['photo']['remote']['id']
				remote_file = self._tg.call_method('getRemoteFile', params={'remote_file_id': remote_file_id})
				time.sleep(timer)
				remote_file.update
				time.sleep(timer)
				file_id = remote_file.update['id']
				file = self._tg.call_method('downloadFile', params={'file_id': file_id, 'priority': 1, 'offset':0, 'limit':10, 'synchronous':True})
				time.sleep(3)
				path = file.update['local']['path']
				return path
			else:
				return None
		except:
			if timer < 2:
				timer += 0.5 
				return self._get_photo_path(message, timer)
			else:
				return None

	def _get_message(self, message):
		if self._signal_image and 'photo' in message['messages'][0]['content'].keys():
			self._signal_image_check = True
			message =  message['messages'][0]['content']['caption']['text']
		else:
			message = message['messages'][0]['content']['text']['text']
		return message

	def _get_chat_history(self, telegram_chat, from_message_id=0):
		chat_id = telegram_chat.update['id']
		result = self._tg.get_chat_history(chat_id=chat_id, offset=0, from_message_id=from_message_id)
		result.wait()
		result.update
		result.wait()
		if result.error:
			return None, result.error, result.error_info
		else:
			return result.update, None, None
# check_chat_id = self._tg.get_chat('-1001490464609')
# chat_id = -1001389557656 #- technicalPips VIP
# chat_id = -1001287502434 #- technicalPips
# check_chat_id = self._tg.call_method('checkChatInviteLink', params={'invite_link': 'https://t.me/joinchat/AAAAAFLS95gUnQM_N75uoA'})
# check_chat_id = self._tg.get_chat('-1001389557656')
# chat_id = -1001159029077 # Swing Trading ViP
# check_chat_id = self._tg.get_chat('-1001222448337')
# chat_id = 60866983
# chat_id = 487330707 #- Breno Perucchi
# chat_id = -481414224 # RoboSignalGroup
# chat_id = -1001436795976 # MirFx
# chat_id = -340961920 # Perucchi Inc	
# chat_id = -1001330590845 # Pip Nation
# chat_id = -1001340273590 # Pip Nation Vip