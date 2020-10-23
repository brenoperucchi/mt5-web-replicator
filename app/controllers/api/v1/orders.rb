require 'json'
module API
  module V1
    class Orders < Grape::API
      include API::V1::Defaults

      resource :orders do
        desc "Return Order Message"
        params do 
          requires :message_id, type: Integer, desc: 'Message ID.'
        end
        route_param :message_id do 
          get do
            order = Order.find_by(message_id: params[:message_id])
          end
        end

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
                                                  lot: params[:lot],
                                                  magic: params[:magic],
                                                  response: params[:response],
                                                  response_error: params[:response_value],
                                                  open_at: params[:open_at],
                                                  meta_order_generate: params[:meta_order_generate]
                                                )

          params[:response].blank? ? transaction.execute : transaction.erro
          transaction
          #   message.update_attribute(:message_response, params.to_json)
          #   message.error
          # end
        end        
        
        desc 'Save message from telegram to rails api'
        post '' do
          logger.debug { "MESSAGE_ID: #{params[:message_id]}" }
          logger.debug { "URL: #{request.env['REQUEST_PATH']}" }
          if (params[:message].downcase.include?('sell') or params[:message].downcase.include?('buy')) and not params[:message].downcase.include?('results')
            signal = Trace.active.find_by(name_id: params[:name_id])
            if signal
              message = signal.orders.find_by(message_id: params[:message_id]) 
              message ||= signal.orders.create(message_id: params[:message_id]) do |order|
                order.message = params[:message]
                if params[:photo_path].present?
                  order.image.attach(io: File.open(params[:photo_path]), filename: 'output.tiff')
                else 
                  order.prepare
                end
              end
            end
          end
        end

      end
    end
  end
end