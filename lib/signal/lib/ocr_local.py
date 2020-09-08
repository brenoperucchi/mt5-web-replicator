from PIL import Image
import pytesseract
import argparse
import cv2
import os
import re
# import pdb

def detect_text_local(path):
	image = cv2.imread(path)
	gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
	gray = cv2.threshold(gray, 0, 255,
		cv2.THRESH_BINARY | cv2.THRESH_OTSU)[1]
	text = pytesseract.image_to_string(gray)
	text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\xff]', '', text)
	text = text.split("\n")
	text = list(filter(None, text))
	text = re.sub(" / ", "",  text[-1]).strip()
	return text
