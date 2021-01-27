load "#{Rails.root}/lib/telegram/signal.rb"
require 'sidekiq-scheduler'

class MetaWorker
  include Sidekiq::Worker
  include Rails.application.routes.url_helpers

  def perform()
  	telegram_request_msg
  end
end