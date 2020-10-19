require 'json'
module API
  module V1
    class Slaves < Grape::API
      include API::V1::Defaults

      resource :slaves do
        desc "Return all signs"
        get "" do
          # return "{\"id\":\"1\",\"provider\":\"-481414224\"}, / {\"id\":\"2\",\"provider\":\"-222222\"},"
          Order.all.to_json(only: [:id, :provider]).delete('[]').gsub("},", "}, / ")
          foo = {'collection'=> Order.all.collect{|x| {id: x.id.to_s}}}.to_json
          # foo = "{ \"firstName\": \"John\", \"lastName\": \"Smith\", \"age\": 25, \"address\": { \"streetAddress\": \"21 2nd Street\", \"city\": \"New York\", \"state\": \"NY\", \"postalCode\": \"10021\" }, \"phoneNumber\": [ { \"type\": \"home\", \"number\": \"212 555-1234\" }, { \"type\": \"fax\", \"number\": \"646 555-4567\" } ], \"gender\":{ \"type\":\"male\" }  }";
          # JSON(foo)
        end
        desc "Return a user"
        params do
          requires :id, type: String, desc: "ID of the user"
        end
        get ":id" do
          Sign.where(id: permitted_params[:id]).first!
        end

        desc 'Create a status.'
        params do
          # requires :provider, type: String, desc: 'Your Provider'
          # requires :kind, type: String, desc: 'Your Type'
          # requires :symbol, type: String, desc: 'Symbol'
          # requires :magic, type: String, desc: 'Magic'
        end
        post do
          Sign.create!({
            provider: params[:provider],
            provider_name: params[:provider_name],
            symbol: params[:symbol],
            action: params[:action],
            kind: params[:kind],
            price_request: params[:price_request],
            price_open: params[:price_open],
            stop_loss: params[:stop_loss],
            take_profit_1: params[:take_profit_1],
            take_profit_2: params[:take_profit_2],
            comment: params[:comment],
            lots: params[:lots],
            magic: params[:magic],
            ticket: params[:ticket],
            open_at: params[:open_at],
            context: params[:context],
            response: params[:response],
            response_value: params[:response_value],
            environment: params[:environment]
          })
        end

      end
    end
  end
end