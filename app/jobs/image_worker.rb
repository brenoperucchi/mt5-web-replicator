require 'sidekiq-scheduler'

class ImageWorker
  include Sidekiq::Worker
  include Rails.application.routes.url_helpers

  def perform()
  	Order.image_to_process.each do |order|
  		# path = ActiveStorage::Blob.service.path_for(message.image.key)
  		text = order.ocr_text(file:true)
  		Order.transaction do
	  		order.symbol = text
  			order.prepare
  			order.save
  		end
  	end
  end
end