#!/usr/bin/env ruby
# require File.expand_path('../../../config/environment', __FILE__)
# load "#{__dir__}/signal.rb"
require 'getoptlong'
require 'rubygems'        # if you use RubyGems
require 'daemons'
# require 'pry'
# require 'pry-byebug'


require "pathname"

ENV["RAILS_ENV"] ||= ENV["RACK_ENV"] || "development"
ENV["NODE_ENV"]  ||= "development"
ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../Gemfile",
  Pathname.new(__FILE__).realpath)


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
    	if arg.downcase == "metatrader"
  			Daemons.run_proc("#{__dir__}/signal.rb -e telegram_request_msg")
		  elsif arg.downcase == "telegram"
		    Daemons.run_proc("#{__dir__}/myserver.rb")
		  end
  end
end

  if ARGV.length > 1
    puts "Missing argument (try --help)"
    exit 0
  end
