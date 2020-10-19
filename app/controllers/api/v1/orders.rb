require 'json'
module API
  module V1
    class Orders < Grape::API
      include API::V1::Defaults

      resource :orders do
        desc "Save"
        post "" do
          order = Order.find_by(message_id: params[:message_id])
          order.transactions.create(ticket: params[:ticket],
                                       action: params[:action],
                                       kind: params[:kind],
                                       symbol: params[:symbol],
                                       price_request: params[:price_request],
                                       price_open: params[:price_open],
                                       stop_loss: params[:stop_loss], 
                                       take_profit: params[:take_profit],
                                       comment: params[:comment],
                                       lot: params[:lot],
                                       magic: params[:magic],
                                       response: params[:response],
                                       response_error: params[:response_error],
                                       open_at: params[:open_at])
            order.order
          # else
          #   message.update_attribute(:message_response, params.to_json)
          #   message.error
          # end
        end        
      end

    end
  end
end