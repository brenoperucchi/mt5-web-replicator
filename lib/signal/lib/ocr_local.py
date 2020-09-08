#import the necessary packages
from PIL import Image
import pytesseract
import argparse
import cv2
import os
import pdb
import re
# construct the argument parse and parse the arguments

def detect_text_local(path):
	# load the example image and convert it to grayscale
	image = cv2.imread(path)
	gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
	# check to see if we should apply thresholding to preprocess the
	# image
	# if args["preprocess"] == "thresh":
	gray = cv2.threshold(gray, 0, 255,
		cv2.THRESH_BINARY | cv2.THRESH_OTSU)[1]
	# make a check to see if median blurring should be done to remove
	# noise
	# elif args["preprocess"] == "blur":
	# gray = cv2.medianBlur(gray, 3)
	# load the image as a PIL/Pillow image, apply OCR, and then delete
	# the temporary file
	text = pytesseract.image_to_string(gray)
	text = re.sub(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f-\xff]', '', text)
	text = text.split("\n")
	text = list(filter(None, text))
	return text[-1]
