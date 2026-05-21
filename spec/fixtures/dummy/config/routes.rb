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
    get "respond_to/index", to: "respond_to#index"
    get "respond_to/json_only", to: "respond_to#json_only"
    get "respond_to/html_only", to: "respond_to#html_only"
    get "respond_to/explicit_json", to: "respond_to#explicit_json"
    get "respond_to/unmapped", to: "respond_to#unmapped"
    post "constant_references/execute", to: "constant_references#execute"
    get "constant_references/range", to: "constant_references#range"
    get "constant_references/pattern", to: "constant_references#pattern"
    get "constant_references/non_compatible", to: "constant_references#non_compatible"
    get "constant_references/missing", to: "constant_references#missing"
    post "nested_params/search", to: "nested_params#search"
    post "nested_params/tags", to: "nested_params#tags"
    post "nested_params/moods", to: "nested_params#moods"
    post "nested_params/nested", to: "nested_params#nested"
    post "nested_params/empty_block", to: "nested_params#empty_block"
    post "nested_params/non_hash_block", to: "nested_params#non_hash_block"
    get "rescued_resources/:id", to: "rescued_resources#show"
    get "rescued_resources_with_view", to: "rescued_resources_with_view#index"
    get "silent_with_rescue", to: "silent_with_rescue#silent_action"
    get "sidecars/with_partial", to: "sidecars#with_partial"
    get "sidecars/inline_render", to: "sidecars#inline_render"
    get "sidecars/no_view", to: "sidecars#no_view"
    get "sidecars/malformed", to: "sidecars#malformed"
    post "binding_helpers/create", to: "binding_helpers#create"
    get "binding_helpers/chain", to: "binding_helpers#chain"
    get "binding_helpers/kwargs", to: "binding_helpers#kwargs"
    get "activity_logs", to: "activity_logs#index"
    get "case_branches/show", to: "case_branches#show"
    post "inputs/upload", to: "inputs#upload"
    resources :inputs, only: %i[show create]
  end

  # A redirect route has no backing controller action — exercises the skip path.
  get "legacy", to: redirect("/api/posts")

  # Points at a controller that does not exist — exercises the resilience path:
  # the run records a warning and still produces an operation for it.
  get "api/orphan", to: "api/orphan#index"
end
