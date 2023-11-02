require 'sidekiq/web'
Rails.application.routes.draw do
  resources :delivery_payments
  constraints subdomain: /.*/ do
    
    get  "stripe/checkout",                           to: "stripe#checkout", as:'checkout_stripe'      
    get  "stripe/webhook/:id/:payment_id",            to: "stripe#webhook"
    post "stripe/webhook/:id/:payment_id",            to: "stripe#webhook"

    get  "mercadopago/webhook/:id/:payment_id",       to: "mercadopago#webhook"
    post "mercadopago/webhook/:id/:payment_id",       to: "mercadopago#webhook"
    post "mercadopago/ipn/:id/:payment_id",           to: "mercadopago#ipn"
    post "mercadopago/process_payment/:invoice_id",   to: "mercadopago#process_payment"
    get  "mercadopago/finish/:invoice_id",            to: "mercadopago#finish",    as: 'finish_mercadopago'
    get  "mercadopago/back_urls/:state/:invoice_id",  to: "mercadopago#back_urls"
    
    get "subscription", to: "pay#subscription"
    get "billing",      to: "pay#billing"

    resources :invoice_items
    resources :customers
    resources :stores
    # "/:store_name/dashboards/"
    #   get  '/all',                      to: 'dashboards#index',           on: :collection 
    #   get  '/:name',                    to: 'dashboards#show',            on: :collection, as: 'show'
    # end

    # resources :dashboards, only: [:index]
    get  '/dashboards/',                     to: 'dashboards#index'#, as: 'index_dasboards'
    get  '/dashboards/all',                  to: 'dashboards#index'#, as: 'index_dasboards'
    get  '/dashboards/:store_name',          to: 'dashboards#index',  as: 'store_name_dasboards'
    get  '/dashboards/:store_name/all',      to: 'dashboards#index'#
    

    resource :dashboard, only: [:show, :create], path:"dashboard/:store_name/:name" do
      get  'account/:account_id',                     to: 'dashboards#account',         on: :collection, as: 'account'
      get  'contract/:promotion',                     to: 'dashboards#contract',        on: :member#, as: 'account'
      get  'contract',                                to: 'dashboards#contract',        on: :member, as: 'contract'
      post 'contract',                                to: 'dashboards#create',          on: :member
      get  'finish/:account_id',                      to: 'dashboards#finish',          on: :member, as: 'finish'
      # get  'finish',                                to: 'dashboards#finish_external_payment',          on: :collection
    end

    # get  '/dashboards/:name/contract',                to: 'dashboards#contract',       as: 'contract_dashboards'

    constraints(name: /[A-Z][A-Z][0-9]+/) do
      resource :robos, controller: 'dashboards', path:"robos/:name"
    end

    
    devise_for :users, controllers: {
      sessions: 'users/sessions',
      registrations: 'users/registrations'
    }
    
    resources :clients
    mount Sidekiq::Web => '/sidekiq'
    mount API::Base, at: "/"
    namespace :control do
      resources :instruments
      resources :accounts
      resources :traces
      resources :orders, except:[:edit, :new, :destroy, :update]
      resources :transactions, only:[:show]
      resources :transaction_slaves, only:[:show]
      resources :customers
      resources :customer_plans
      resources :payments
      resources :invoices, except:[:new]
      resources :loggings, only:[:show]
      resources :stores

      root "orders#index"
    end

    namespace :admin do
      resources :accounts
      resources :account_servers

      # resources :deals
      # resources :messages, as: :message_metatrader #, only: [:index]
      # resources :message_metatrader, controller: :messages, type:'Message::Metatrader'
      # get '/messages', to: 'messages#index', as: 'messages', on: :collection
      # end
      
      resources :customers
      resources :customer_plans
      resources :instruments
      resources :invoice_items
      resources :loggings
        # resources :messages
        # resources :metatraders
      namespace :message do
        resources :messages
      end
      namespace :paper_trail do
        resources :versions
      end
      resources :orders#, except:[:edit]
      resources :payment_methods
      resources :payments
      resources :plans
      resources :plan_items
      resources :plan_usages, except: [:index]
      resources :invoices do
         get :invoice_send, on: :member
      end           
      resources :stores
      resources :traces
      resources :transactions
    	resources :transaction_slaves
      resources :users
      resources :upload_files
      
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
