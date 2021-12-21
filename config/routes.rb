# require 'sidekiq/web'
Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: 'users/sessions'
  }
  resources :clients
  # mount Sidekiq::Web => '/sidekiq'
  mount API::Base, at: "/"
  namespace :admin do
	  	resources :transaction_slaves
      resources :transactions
      resources :loggings
      resources :instruments

      resources :orders
      resources :messages#, only: [:index]
      # get '/messages', to: 'messages#index', as: 'messages', on: :collection
      # end
      
      resources :traces
      resources :stores
      resources :accounts
      # resources :sign_traces
	    
	    root "orders#index"
    end
  
  # get ':page' => 'signs#show', as: 'signs'
  root :to => "pages#index" 
  # root 'admin/orders#index'
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html

end
