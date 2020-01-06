Rails.application.routes.draw do
  namespace :admin do
          resources :signs

      root to: "signs#show"
    end
  resources :apisocials
  
  get ':page' => 'signs#show', as: 'signs'
  root 'admin/signs#index'
  # For details on the DSL available within this file, see https://guides.rubyonrails.org/routing.html

end
