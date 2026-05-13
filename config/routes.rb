Rails.application.routes.draw do
  resource :session, only: [:new, :create, :destroy] do
    collection do
      get :consume
      get :check_email
      get :code
      post :code, action: :submit_code
    end
  end
  # When the admin subdomain is hit (admin.<APP_HOST>), land directly on
  # /admin instead of the PWA home. Same app, just a host-driven shortcut.
  app_host = ENV.fetch("APP_HOST", "localhost")
  unless app_host == "localhost"
    constraints(host: "admin.#{app_host}") do
      root to: redirect("/admin"), as: :admin_host_root
    end
  end
  root "home#index"

  get "/manifest.webmanifest", to: "pwa#manifest"

  namespace :organizers do
    resources :tournaments do
      resources :tournament_entries, only: [:create, :update, :destroy] do
        resources :tournament_entry_members, only: [:create, :destroy]
      end
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

  namespace :admin do
    root to: "dashboards#index"
    resources :clubs, only: [ :index, :show, :new, :create, :edit, :update ] do
      scope module: :clubs do
        resources :members, only: [:index, :new, :create] do
          member do
            post :issue_code
            get  :code
          end
        end
        resources :tournaments, only: [:index, :show]
        resources :catches, only: [:index]
        resources :tournament_templates, only: [:index, :show]
        resources :rules, only: [:index, :show] do
          collection { get :history }
        end
      end
    end
    resources :tournaments do
      resources :tournament_entries, only: [:create, :update, :destroy] do
        resources :tournament_entry_members, only: [:create, :destroy]
      end
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
    resources :rules, only: [ :index, :new, :create, :show ] do
      collection do
        get  :history
        post :set_active_season
      end
    end
  end

  resources :tournaments, only: [:index, :show] do
    collection { get :archived }
    scope module: :tournaments do
      resources :catches, only: [:show]
    end
  end
  resources :catches, only: [:index, :new, :create, :show, :update] do
    collection do
      get :map
      get :select_teammate
    end
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
  get "/rules", to: "rules#show", as: :rules
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
