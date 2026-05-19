# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :api do
    resources :users, only: %i[index show create destroy]
    resources :posts, only: %i[index]
    resources :pages, only: %i[show] do
      get :download, on: :member
    end
    get "reports/single", to: "reports#single"
    get "reports/chained", to: "reports#chained"
    get "reports/via_concern", to: "reports#via_concern"
    get "reports/cyclic", to: "reports#cyclic"
    post "statuses/mark", to: "statuses#mark"
    put "statuses/unmark", to: "statuses#unmark"
    post "statuses/make", to: "statuses#make"
    post "statuses/guarded", to: "statuses#guarded"
  end

  # A redirect route has no backing controller action — exercises the skip path.
  get "legacy", to: redirect("/api/posts")

  # Points at a controller that does not exist — exercises the resilience path:
  # the run records a warning and still produces an operation for it.
  get "api/orphan", to: "api/orphan#index"
end
