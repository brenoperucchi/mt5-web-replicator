require 'json'
module API
  module V1
    class SignOrders < Grape::API
      include API::V1::Defaults

      resource :sign_orders do
        desc "Save"
        post "" do
          message = SignOrder.find_by(message_id: params[:message_id])
          if params[:response].present?
            message.update_attribute(:message_response, params.to_json)
            message.erro
          else
            message.update_attribute(:message_response, params.to_json)
            message.order
          end
        end      
      end
    end
  end
end