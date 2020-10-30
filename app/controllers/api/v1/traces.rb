require 'json'
module API
  module V1
    class Traces < Grape::API
      include API::V1::Defaults

      resource :traces do
        desc "Return all signs"
        get "" do
          # return "{\"id\":\"1\",\"provider\":\"-481414224\"}, / {\"id\":\"2\",\"provider\":\"-222222\"},"
          Trace.all.to_json(only: [:id, :provider]).delete('[]').gsub("},", "}, / ")
          foo = {'collection'=> Trace.all.collect{|x| {id: x.id.to_s}}}
          # foo = "{ \"firstName\": \"John\", \"lastName\": \"Smith\", \"age\": 25, \"address\": { \"streetAddress\": \"21 2nd Street\", \"city\": \"New York\", \"state\": \"NY\", \"postalCode\": \"10021\" }, \"phoneNumber\": [ { \"type\": \"home\", \"number\": \"212 555-1234\" }, { \"type\": \"fax\", \"number\": \"646 555-4567\" } ], \"gender\":{ \"type\":\"male\" }  }";
          # JSON(foo)
          # return "{\"id\":\"1\",\"provider\":\"-481414224\"}, / {\"id\":\"2\",\"provider\":\"-222222\"},"
          # Trace.all.to_json(only: [:id, :provider]).delete('[]').gsub("},", "}, / ")
          # foo = {'collection'=> Trace.all.collect{|x| {id: x.id.to_s}}}
          # foo = "{ \"firstName\": \"John\", \"lastName\": \"Smith\", \"age\": 25, \"address\": { \"streetAddress\": \"21 2nd Street\", \"city\": \"New York\", \"state\": \"NY\", \"postalCode\": \"10021\" }, \"phoneNumber\": [ { \"type\": \"home\", \"number\": \"212 555-1234\" }, { \"type\": \"fax\", \"number\": \"646 555-4567\" } ], \"gender\":{ \"type\":\"male\" }  }";
          # JSON(foo)
        end

        desc "Return all signs"
        post "/master" do
          response = params[:message].split("|")
          store = Store.all.detect{|x| x.master == response[0]}
          if store
            transaction = Transaction.find_by(ticket: response[3])
            if transaction
              transaction.update(profit:response[10], response: params[:message], action: response[1])
              transaction.close
            end
          end
        end
      
      end
    end
  end
end