from PIL import Image
import pytesseract
import argparse
import cv2
import os
import re, pdb
import subprocess

def detect_text_local(path):
	try:
		bashCommand = f"/Users/brenoperucchi/Devs/telegram/lib/signal/images/textcleaner -c '0,140,0,0' -g -t 30 -s 2 -u -p 5 -T {path} /Users/brenoperucchi/Devs/telegram/lib/signal/images/data/output.tiff"
		output = subprocess.check_output(['bash','-c', bashCommand])
		image = Image.open("/Users/brenoperucchi/Devs/telegram/lib/signal/images/data/output.tiff")
		text = pytesseract.image_to_string(image)
		text = re.sub("[^A-Za-z]+", "",  text)
		return text
	except Exception as e:
		print("Error Detect text local: ", e)