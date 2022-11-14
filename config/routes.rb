require 'sidekiq/web'
Rails.application.routes.draw do
  constraints subdomain: /.*/ do
    resources :invoice_items
    # post "create_checkout", to: "charge#checkout"
    # get "checkout",       to: "charge#index"
    post "stripe/webhook",  to: "charge#webhook"
    get "checkout",         as:'checkout_charge',      to: "charge#checkout"
    
    # get "checkout", to: "pay#checkout"
    get "subscription", to: "pay#subscription"
    get "billing", to: "pay#billing"

    resources :customers
    resources :stores
    resources :dashboards, only: [:index, :show] do
      get 'account/:id/:trace_id', to: 'dashboards#account', on: :collection, as: 'account'
    end
    devise_for :users, controllers: {
      sessions: 'users/sessions',
      registrations: 'users/registrations'
    }
    resources :clients
    mount Sidekiq::Web => '/sidekiq'
    mount API::Base, at: "/"
    namespace :control do
      resources :stores
      resources :customers
      resources :accounts
      resources :instruments
      resources :traces
      resources :transactions, except:[:edit, :new]
      resources :invoices, except:[:new]
    end
    namespace :admin do
      namespace :paper_trail do
        resources :versions
      end
      resources :customers
      resources :invoices do
         get :invoice_send, on: :member
      end      
     
      resources :invoice_items
    	resources :transaction_slaves
      resources :transactions
      resources :loggings
      resources :instruments

      resources :orders#, except:[:edit]
      resources :deals
      resources :messages#, only: [:index]
      resources :message_metatrader, controller: :messages, type:'Message::Metatrader'
      # get '/messages', to: 'messages#index', as: 'messages', on: :collection
      # end
      
      resources :traces
      resources :stores
      resources :accounts
      resources :users
      # resources :sign_traces
      
      root "orders#index"
    end
  end    
  # get ':page' => 'signs#show', as: 'signs'
  get "site", to:"site#index"
  root :to => "dashboards#index" 
  # root 'admin/orders#index'
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html

end
