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
    resources :dashboards, only: [:index, :show, :create] do
      get 'account/:id/:trace_id',       to: 'dashboards#account',         on: :collection, as: 'account'
      get '/contract',                   to: 'dashboards#contract',        on: :member, as: 'contract'
      post '/contract',                  to: 'dashboards#create',          on: :member
      get 'finish_contract/:account_id', to: 'dashboards#finish_contract', on: :member
    end
    devise_for :users, controllers: {
      sessions: 'users/sessions',
      registrations: 'users/registrations'
    }
    resources :clients
    mount Sidekiq::Web => '/sidekiq'
    mount API::Base, at: "/"
    namespace :control do
      resources :accounts
      resources :traces
      resources :orders, except:[:edit, :new, :destroy, :update]
      resources :instruments
      resources :transactions, only:[:show]
      resources :loggings, only:[:show]
      resources :transaction_slaves, only:[:show]
      resources :invoices, except:[:new]
      resources :customers
      resources :customer_plans
      resources :stores
    end

    namespace :admin do
      namespace :message do
        # resources :messages
        resources :metatraders
      end
      namespace :paper_trail do
        resources :versions
      end
      resources :customers
      resources :plans
      resources :plan_items
      resources :invoices do
         get :invoice_send, on: :member
      end      
     
      resources :invoice_items
      resources :customer_plans
    	resources :transaction_slaves
      resources :transactions
      resources :loggings
      resources :instruments

      resources :orders#, except:[:edit]
      # resources :deals
      # resources :messages, as: :message_metatrader #, only: [:index]
      # resources :message_metatrader, controller: :messages, type:'Message::Metatrader'
      # get '/messages', to: 'messages#index', as: 'messages', on: :collection
      # end
      
      resources :traces
      resources :accounts
      resources :account_servers
      resources :users
      resources :stores
      # resources :sign_traces
      
      root "orders#index"
    end
  end

  # get ':page' => 'signs#show', as: 'signs'
  post "create_store",      to:"site#create_store"
  get  "support",           to:"site#support"
  get  "demo_request",      to:"site#demo_request"
  get  "robos",             to:"site#robos"

  root :to => "site#index" 
  # root 'admin/orders#index'
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html

end
