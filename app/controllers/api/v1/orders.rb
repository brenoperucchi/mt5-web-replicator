require 'open-uri'
require 'json'
module API
  module V1
    class Orders < Grape::API
      include API::V1::Defaults

      resource :orders do

        ############################################
        desc "Return Order Message"
        params do 
          requires :message_id, type: Integer, desc: 'Message ID.'
        end
        route_param :message_id do 
          get do
            order = Order.find_by(message_id: params[:message_id])
          end
        end
        
        ############################################
        desc "Save transaction from metatrader order"
        post "transaction/" do
          order = Order.find_by(message_id: params[:message_id])
          transaction = order.transactions.create(
                                                  ticket: params[:ticket],
                                                  action: params[:action],
                                                  kind: params[:kind],
                                                  symbol: params[:symbol],
                                                  price_request: params[:price_request],
                                                  price_open: params[:price_open],
                                                  stop_loss: params[:stop_loss], 
                                                  take_profit: params[:take_profit],
                                                  lot: params[:lot],
                                                  comment: params[:comment],
                                                  magic: params[:magic],
                                                  response: params[:response],
                                                  response_error: params[:response_value],
                                                  open_at: params[:open_at],
                                                  meta_order_generate: params[:meta_order_generate]
                                                )
          params[:response].blank? ? transaction.execute : transaction.erro
          transaction
        end        
        
        ############################################
        desc 'Save message from telegram to rails api'
        post '' do
          logger.debug { "MESSAGE_ID: #{params[:message_id]}" }
          logger.debug { "URL: #{request.env['REQUEST_PATH']}" }
          signal = Trace.active.find_by(name_id: params[:name_id])
          if signal
            message = signal.orders.find_by(message_id: params[:message_id]) 
            message ||= signal.orders.create(message_id: params[:message_id]) do |order|
              order.message = params[:message].html_safe
              case order.trace.name
              when "M15 Signals Premium", "RoboSignal"
                if (params[:message].downcase.include?('sell') or params[:message].downcase.include?('buy')) and not params[:message].downcase.include?('results')
                  open("#{Rails.root}/public/output.jpg", 'wb') { |file| file << open(params[:photo_path]).read }
                  order.symbol = order.ocr_text(file:true) 
                  order.image.attach(io: File.open("#{Rails.root}/public/output.jpg"), filename: "#{order.symbol}.jpg") 
                  order.save if order.prepare and order.order
                end
              when "Swing Trading ViP"
                if (params[:message].downcase.include?('sell') or params[:message].downcase.include?('buy')) and params[:message].downcase.include?('now')
                  order.symbol = params[:message].split[0].upcase
                  order.save if order.prepare and order.order
                end
              when "Mirfx", "Perucchi Inc"
                if (params[:message].downcase.include?('sell') or params[:message].downcase.include?('buy')) and params[:message].downcase.include?('*novo trade*')
                  order.symbol = params[:message].split[3].upcase
                  order.save if order.prepare and order.order
                end
              end
            end
          end
        end

      end
    end
  end
end