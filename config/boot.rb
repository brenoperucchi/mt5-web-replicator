ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "logger" # concurrent-ruby >= 1.3.5 no longer requires this transitively, which activesupport 6.1 depends on.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
