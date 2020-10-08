require 'json'
module API
  module V1
    class Stores < Grape::API
      include API::V1::Defaults

      resource :stores do
        desc "Return all signs"
        get "" do
          Store.first
        end      
      end
    end
  end
end