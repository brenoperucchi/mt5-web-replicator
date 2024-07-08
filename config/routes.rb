require 'sidekiq/web'
Rails.application.routes.draw do
  resources :delivery_payments
  constraints subdomain: /.*/ do
    
    get  "stripe/checkout",                           to: "stripe#checkout", as:'checkout_stripe'      
    get  "stripe/webhook/:store_id/:payment_id",            to: "stripe#webhook"
    post "stripe/webhook/:store_id/:payment_id",            to: "stripe#webhook"

    get  "mercadopago/webhook/:store_id/:payment_id",       to: "mercadopago#webhook"
    post "mercadopago/webhook/:store_id/:payment_id",       to: "mercadopago#webhook"
    post "mercadopago/ipn/:store_id/:payment_id",           to: "mercadopago#ipn"
    post "mercadopago/process_payment/:invoice_id",   to: "mercadopago#process_payment"
    get  "mercadopago/finish/:invoice_id",            to: "mercadopago#finish",    as: 'finish_mercadopago'
    get  "mercadopago/back_urls/:state/:invoice_id",  to: "mercadopago#back_urls"
    
    get "subscription", to: "pay#subscription"
    get "billing",      to: "pay#billing"

    resources :invoice_items
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
      get  :account_admin,                            on: :collection
      get  'account/:account_id/:transaction_id',     to: 'dashboards#transaction',     on: :collection, as: 'transaction'
      get  'account/:account_id',                     to: 'dashboards#account',         on: :collection, as: 'account'
      get  'contract/:promotion',                     to: 'dashboards#contract',        on: :member#, as: 'account'
      get  'contract',                                to: 'dashboards#contract',        on: :member, as: 'contract'
      get  'mfes',                                    to: 'dashboards#mfe',           on: :member, as: 'mfes'
      get  'mfes/:kind/:date',                        to: 'dashboards#mfe',           on: :collection, as: 'mfe_by'
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

    # devise_scope :user do
    #   # get '/customer',   to: 'sessions#new'
    #   get 'control/login',      to: 'control/sessions#new',    as: 'new_session'
    #   post 'control/login',     to: 'control/sessions#create', as: 'session'
    #   delete 'control/logout',  to: 'control/sessions#destroy', as: 'destroy_session'
    # end
  
    # resources :clients
    
    mount Sidekiq::Web => '/sidekiq'
    mount API::Base, at: "/"

    namespace :panel do
      # devise_for :users, excepted: %w[sessions#new session#destroy]

      devise_for :user,  controller: {
        sessions: 'panel/sessions'
      }

      devise_scope :user do
        # get '/customer',   to: 'sessions#new'
        get 'login',      to: 'sessions#new',    as: 'new_session'
        post 'login',     to: 'sessions#create', as: 'session'
        delete 'logout',  to: 'sessions#destroy', as: 'destroy_session'
      end

      resources :dashboard, only: [:index] do
        get 'back_url/:store_name/:state/:invoice_id' , to: 'dashboard#back_url', as: 'back_url', on: :collection
      end
      
      resources :invoices, only: [:index] do
        get  'invoice_send', to: 'invoices#invoice_send', on: :member, as: 'invoice_send'
        get  'item_conciliated/:item_id', to: 'invoices#item_conciliated', on: :member, as: 'item_conciliated'
      end

      root "dashboard#index"
    end

    namespace :control do
      resources :instruments
      resources :accounts
      resources :customers
      resources :customer_plans
      resources :invoices, except:[:new]
      resources :loggings, only:[:show]
      resources :transaction_slaves, except:[:edit, :new, :destroy, :update]
      resources :orders
      resources :transactions, only:[:show]
      resources :transaction_slaves, only:[:show]
      resources :stores
      resources :payments

      root "orders#index"
    end

    namespace :admin do
      resources :instruments
      resources :accounts
      resources :account_servers

      # resources :deals
      # resources :messages, as: :message_metatrader #, only: [:index]
      # resources :message_metatrader, controller: :messages, type:'Message::Metatrader'
      # get '/messages', to: 'messages#index', as: 'messages', on: :collection
      # end
      
      resources :customers
      resources :customer_plans
      resources :invoices do
         get :invoice_send, on: :member
         get :conciliate_orders, on: :member
      end           
      resources :invoice_items do
        get 'show_conciliated', on: :member
      end
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
      resources :plans
      resources :plan_items
      resources :plan_usages, except: [:index]
      resources :traces
      resources :stores
      resources :payment_methods
      resources :payments
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
