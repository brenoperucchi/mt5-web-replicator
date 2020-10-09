require 'sidekiq-scheduler'

class ImageWorker
  include Sidekiq::Worker
  include Rails.application.routes.url_helpers

  def perform()
  	SignOrder.image_to_process.each do |order|
  		# path = ActiveStorage::Blob.service.path_for(message.image.key)
  		text = order.ocr_text(file:true)
  		SignOrder.transaction do
	  		order.symbol = text
  			order.process
  			order.save
  		end
  	end
  end
end