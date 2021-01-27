#!/usr/bin/env ruby
# require File.expand_path('../../../config/environment', __FILE__)
# load "#{__dir__}/signal.rb"
require 'getoptlong'
require 'rubygems'        # if you use RubyGems
require 'daemons'
# require 'pry'
# require 'pry-byebug'


require "pathname"
Daemons.run_proc("#{__dir__}/signal.rb -e meta_send_order")
