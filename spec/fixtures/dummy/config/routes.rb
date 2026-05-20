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
    post "redirects/create", to: "redirects#create"
    post "redirects/transfer", to: "redirects#transfer"
    get "redirects/old_path", to: "redirects#old_path"
    post "redirects/bounce", to: "redirects#bounce"
    post "redirects/mixed", to: "redirects#mixed"
    patch "multi_status/update", to: "multi_status#update"
    post "multi_status/dup_same", to: "multi_status#dup_same"
    post "multi_status/dup_distinct", to: "multi_status#dup_distinct"
    post "multi_status/head_and_render", to: "multi_status#head_and_render"
    get "multi_status/show/:id", to: "multi_status#show"
    delete "multi_status/destroy/:id", to: "multi_status#destroy"
    put "template_renders/update", to: "template_renders#update"
    get "template_renders/as_html", to: "template_renders#as_html"
    get "template_renders/missing", to: "template_renders#missing"
    delete "template_renders/destroy/:id", to: "template_renders#destroy"
    post "inputs/upload", to: "inputs#upload"
    resources :inputs, only: %i[show create]
  end

  # A redirect route has no backing controller action — exercises the skip path.
  get "legacy", to: redirect("/api/posts")

  # Points at a controller that does not exist — exercises the resilience path:
  # the run records a warning and still produces an operation for it.
  get "api/orphan", to: "api/orphan#index"
end
