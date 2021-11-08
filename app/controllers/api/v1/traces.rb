require 'csv'
require 'json'
module API
  module V1
    class Traces < Grape::API
      include API::V1::Defaults

      resource :traces do
        desc "Return all signs"
        get "/:account_id" do
          account = Account.find_by(name: params[:account_id])
          if account
            map = account.transactions.executed.collect do |t| 
              attributes = t.meta_attributes
              "#{attributes[:trace_id]}|#{attributes[:instrument]}|#{attributes[:transaction_id]}|#{attributes[:ordertype]}|#{attributes[:openprice]}|#{attributes[:volume]}|#{attributes[:stoploss]}|#{attributes[:takeprofit]}|#{attributes[:magic_number]}"
            end.join('/')
          end
          content_type 'text/plain'
          body map

          # # return "{\"id\":\"1\",\"provider\":\"-481414224\"}, / {\"id\":\"2\",\"provider\":\"-222222\"},"
          # # Trace.all.to_json(only: [:id, :provider]).delete('[]').gsub("},", "}, / ")
          # # foo = {'collection'=> Trace.all.collect{|x| {id: x.id.to_s}}}


          # map = Store.first.transactions.executed.collect{|x| "#{x.order_id}|#{x.price_request}|#{x.symbol}"}
          # {'collection'=> map}
          # foo = "{ \"firstName\": \"John\", \"lastName\": \"Smith\", \"age\": 25, \"address\": { \"streetAddress\": \"21 2nd Street\", \"city\": \"New York\", \"state\": \"NY\", \"postalCode\": \"10021\" }, \"phoneNumber\": [ { \"type\": \"home\", \"number\": \"212 555-1234\" }, { \"type\": \"fax\", \"number\": \"646 555-4567\" } ], \"gender\":{ \"type\":\"male\" }  }";
          # JSON(foo)
          # return "{\"id\":\"1\",\"provider\":\"-481414224\"}, / {\"id\":\"2\",\"provider\":\"-222222\"},"
          # Trace.all.to_json(only: [:id, :provider]).delete('[]').gsub("},", "}, / ")
          # foo = {'collection'=> Trace.all.collect{|x| {id: x.id.to_s}}}
          # foo = "{ \"firstName\": \"John\", \"lastName\": \"Smith\", \"age\": 25, \"address\": { \"streetAddress\": \"21 2nd Street\", \"city\": \"New York\", \"state\": \"NY\", \"postalCode\": \"10021\" }, \"phoneNumber\": [ { \"type\": \"home\", \"number\": \"212 555-1234\" }, { \"type\": \"fax\", \"number\": \"646 555-4567\" } ], \"gender\":{ \"type\":\"male\" }  }";
          # JSON(foo)
        end

        desc "Post and Return Traces"
        post "/:account_id" do
          account = Account.find_by(name: params[:account_id])
          if account
            map = account.transactions.executed.collect do |t| 
              attributes = t.meta_attributes
              "#{attributes[:trace_id]}|#{attributes[:instrument]}|#{attributes[:transaction_id]}|#{attributes[:ordertype]}|#{attributes[:openprice]}|#{attributes[:volume]}|#{attributes[:stoploss]}|#{attributes[:takeprofit]}|#{attributes[:magic_number]}"
            end.join('/')
          end
          content_type 'text/plain'
          body map
        end   
      end
    end
  end
end