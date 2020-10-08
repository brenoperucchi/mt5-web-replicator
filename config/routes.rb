require 'sidekiq/web'
Rails.application.routes.draw do
  mount Sidekiq::Web => '/sidekiq'
  mount API::Base, at: "/"
  namespace :admin do
	  	resources :sign_slaves
      resources :sign_orders
      resources :sign_traces
      # resources :sign_traces
	    
	    root "sign_orders#index"
    end
  resources :apisocials
  
  get ':page' => 'signs#show', as: 'signs'
  root 'admin/sign_orders#index'
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html

end
