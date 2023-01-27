#!/usr/bin/env ruby
# encoding: Windows-1252
# require 'open-uri'
require 'json'
require 'fileutils'
require File.expand_path('../../config/environment', __FILE__)
require 'pry'
require "faraday"
require 'uri'

# while true

file="#{Rails.root}/public/mntpoint/signal_copy_trasmit.txt"
file_tmp="#{Rails.root}/public/mntpoint/signal_copy_trasmit.txt.tmp"
line_num=0

# text = File.open(file, 'rb').read
# text=File.open(file, "rb:ASCII-8BIT") {|f| [f.read].pack("H*")} 
# text=File.open(file, 'rb').read
# # text.gsub!(/\r\n?/, "\n")
# string = ""
# text.each_line do |line|
#   string << line
# end
# File.open(file).each do |line|
#   print "#{line_num += 1} #{line.chomp}"
# end
# while(line=file.gets)
# 	puts line
# end


count = 0 
File.write(file_tmp, File.open(file, 'rb').read)
while true
	unless FileUtils.compare_file(file, file_tmp)
		File.write(file_tmp, File.open(file, 'rb').read)
		file = File.open(file_tmp).read
		file.split("\r\n").each_with_index do |line, file_index|
			puts "file_index: #{file_index}"
			puts "count: #{count}"
			if file_index > count
				puts "Index #{file_index}: Line #{line}"
		  	# count = file_index
		  	if line.include?('CLOSED')
		  		url = "http://localhost:8080/api/v1/transactions/copy/trasmit/signal_copy/2_03/closed/3000033103/HEDGING"
		  	else
		  		url = "http://localhost:8080/api/v1/transactions/copy/trasmit/signal_copy/2_03/orders/3000033103/HEDGING"
		  	end
		  	response = Faraday.post(url)  do |request|
		    	request.body = line
		  	end
		  end
		end
	end
end

# while true
# 	count +=1
# 	puts "File Size: #{file_size}"
# 	puts "File Size Tmp: #{file_size_tmp}"
# 	file_size = File.open(file, 'r').read.size
# 	if file_size != file_size_tmp
# 		file_size_tmp = File.open(file_tmp, 'rb').read.size
# 		File.open(file_tmp) do|file|
# 		  until file.eof?
# 		    buffer = file.read
# 		    puts buffer
# 		    binding.pry
# 		    # Do something with buffer
# 		    # puts buffer
# 		  end
# 		  File.write(file_tmp, File.open(file, 'rb').read)
# 		  file_size_tmp = File.open(file_tmp, 'rb').read.size
# 		end
# 	end
# end

# size = 0
# text = File.open(file, 'rb').read
# while size |= size_file
# 	File.open("#{Rails.root}/public/mntpoint/signal_copy_trasmit.txt", 'rb') do |io|
# 	  # while chunk = io.read(16 * 1024200) do
# 	  	# puts io.read
# 	  	size_file
# 	  	puts io.read
# 	    # like stream it across a network
# 	    # or write it to another file:
# 	    # other_io.write chunk
# 	  # end
# 	end
# # end