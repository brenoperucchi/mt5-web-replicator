# load "#{Rails.root}/lib/telegram/signal.rb"
# require 'sidekiq-scheduler'

# class TelegramWorker
#   include Sidekiq::Worker
#   include Rails.application.routes.url_helpers

#   def perform()
#   	meta_send_order
#   end
# end