Rails.application.routes.draw do
  resource :session, only: [:new, :create, :destroy] do
    collection do
      get :consume
      get :check_email
      get :code
      post :code, action: :submit_code
    end
  end
  root "home#index"

  get "/manifest.webmanifest", to: "pwa#manifest"

  namespace :organizers do
    resources :tournaments do
      resources :tournament_entries, only: [:create, :destroy]
      resources :tournament_judges,  only: [:create, :destroy]
    end
    resources :members, only: [:index, :new, :create, :destroy] do
      member do
        post :reactivate
        post :issue_code
        get  :code
      end
    end
    resources :catches, only: [:index]
    resources :tournament_templates do
      member { post :clone }
    end
  end

  resources :tournaments, only: [:index, :show] do
    collection { get :archived }
  end
  resources :catches, only: [:index, :new, :create, :show, :update] do
    collection { get :map }
  end

  namespace :judges do
    resources :tournaments, only: [] do
      resources :catches, only: [:index, :show] do
        resource :review,          only: [:create]
        resource :manual_override, only: [:new, :create]
      end
    end
  end

  namespace :api do
    resources :catches, only: [:create]
    post   "push_subscriptions", to: "push_subscriptions#create"
    delete "push_subscriptions", to: "push_subscriptions#destroy"
  end

  get "season-points",             to: "season_points#show",        as: :season_points
  get "season-points/tournaments", to: "season_points#tournaments", as: :season_points_tournaments

  get "/pre_trip", to: "pre_trip#show", as: :pre_trip
  patch "/me", to: "users#update", as: :me

  resource :notification_settings, only: [:show], controller: :notification_settings do
    collection do
      post :snooze
      post :unmute
      post :mute_tournament
      post :unmute_tournament
    end
  end
end
