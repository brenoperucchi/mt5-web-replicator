require 'json'
module API
  module V1
    class Traces < Grape::API
      include API::V1::Defaults

      resource :traces do
        desc "Return all signs"
        get "" do
          # return "{\"id\":\"1\",\"provider\":\"-481414224\"}, / {\"id\":\"2\",\"provider\":\"-222222\"},"
          Sign.all.to_json(only: [:id, :provider]).delete('[]').gsub("},", "}, / ")
          foo = {'collection'=> Sign.all.collect{|x| {id: x.id.to_s}}}.to_json
          # foo = "{ \"firstName\": \"John\", \"lastName\": \"Smith\", \"age\": 25, \"address\": { \"streetAddress\": \"21 2nd Street\", \"city\": \"New York\", \"state\": \"NY\", \"postalCode\": \"10021\" }, \"phoneNumber\": [ { \"type\": \"home\", \"number\": \"212 555-1234\" }, { \"type\": \"fax\", \"number\": \"646 555-4567\" } ], \"gender\":{ \"type\":\"male\" }  }";
          # JSON(foo)
        end
        # params do
        #   requires :message_id, type: String, desc: "need Message ID"
        # end

        desc "Return Signal Message"
        params do 
          requires :message_id, type: Integer, desc: 'Message ID.'
        end
        route_param :message_id do 
          get do
            Order.find_by(message_id: params[:message_id])
          end
        end

        desc 'Create Traces.'
        params do
          # requires :provider, type: String, desc: 'Your Provider'
          # requires :kind, type: String, desc: 'Your Type'
          # requires :symbol, type: String, desc: 'Symbol'
          # requires :magic, type: String, desc: 'Magic'
        end
        post do
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
                  order.process
                end
              end
            end
          end
        end
      
      end
    end
  end
end