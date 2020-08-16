Rails.application.routes.draw do
  namespace :admin do
	  	resources :signs
		  resources :posts
	    
	    root to: "posts#index"
    end
  resources :apisocials
  resources :posts
  
  get ':page' => 'signs#show', as: 'signs'
  root 'admin/posts#index'
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html

end
