# frozen_string_literal: true

Rails.application.routes.draw do
  namespace :api do
    resources :users, only: %i[index show create]
    resources :posts, only: %i[index]
  end

  # A redirect route has no backing controller action — exercises the skip path.
  get "legacy", to: redirect("/api/posts")

  # Points at a controller that does not exist — exercises the resilience path:
  # the run records a warning and still produces an operation for it.
  get "api/orphan", to: "api/orphan#index"
end
