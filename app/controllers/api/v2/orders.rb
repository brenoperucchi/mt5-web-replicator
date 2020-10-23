require 'json'
module API
  module V2
    class Orders < Grape::API
      include API::V2::Defaults

      resource :orders do
        desc "Return Order Message"
        params do 
          requires :message_id, type: Integer, desc: 'Message ID.'
        end
        route_param :message_id do 
          get do
            order = Order.find_by(message_id: params[:message_id])
            if order 
              return "Signals::#{"#{order.trace.name}Serializer".to_underscore.classify}".constantize.new(order)
            end
          end
        end

      end
    end
  end
end