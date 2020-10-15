require 'json'
module API
  module V1
    class SignTraces < Grape::API
      include API::V1::Defaults

      resource :sign_traces do
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
            SignOrder.find_by(message_id: params[:message_id])
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
          if (params[:message].downcase.include?('sell') or params[:message].downcase.include?('buy')) and not params[:message].downcase.include?('results')
            signal = SignTrace.active.find_by(name_id: params[:name_id])
            if signal
              message = signal.orders.find_by(message_id: params[:message_id]) 
              message ||= signal.orders.create(message_id: params[:message_id]) do |sign_order|
                sign_order.message = params[:message]
                if params[:photo_path].present?
                  sign_order.image.attach(io: File.open(params[:photo_path]), filename: 'output.tiff')
                else 
                  sign_order.process
                end
              end
            end
          end
        end
      
      end
    end
  end
end