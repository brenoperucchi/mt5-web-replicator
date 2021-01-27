#!/usr/bin/env ruby
# require File.expand_path('../../../config/environment', __FILE__)
load "#{__dir__}/signal.rb"
require 'getoptlong'

opts = GetoptLong.new(
  [ '--help', '-h', GetoptLong::NO_ARGUMENT ],
  [ '--name', '-n', GetoptLong::OPTIONAL_ARGUMENT ]
)

opts.each do |opt, arg|
  case opt
    when '--help'
      puts <<-EOF
		-h, --help:
		   show help
		-n, --name:
		   Telegram or MetaTrader options

      EOF
    when '--name', '-n'
    	if arg.downcase == "metatrader" or arg.downcase == "meta_trader"
			meta_send_order
		end
    	if arg.downcase == "telegram"
			telegram_request_msg 
		end
  end
end

if ARGV.length > 1
  puts "Missing argument (try --help)"
  exit 0
end
