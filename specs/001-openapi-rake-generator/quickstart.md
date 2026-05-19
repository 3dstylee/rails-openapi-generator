# Quickstart: OpenAPI Rake Generator

How a Rails developer uses the gem once it is built.

## 1. Install

Add the gem to the host application's `Gemfile`:

```ruby
gem "rails-openapi-generator"
```

```sh
bundle install
```

The gem's railtie registers the `openapi:generate` rake task automatically — no
`Rakefile` change is needed.

## 2. (Optional) Configure

Create `config/initializers/rails_openapi_generator.rb`:

```ruby
RailsOpenapiGenerator.configure do |config|
  config.output_path  = "doc/openapi.yaml"
  config.title        = "My Store API"
  config.api_version  = "2.0.0"
  config.route_filter = ->(route) { route.path.start_with?("/api/") }
end
```

Without an initializer, defaults apply: `doc/openapi.json`, all routes included.

## 3. Document endpoints (already done if you use rails_param + YARD)

```ruby
class Api::UsersController < ApplicationController
  # Search users
  # Returns the users matching the given filters, newest first.
  def index
    param! :query,    String,  blank: false
    param! :per_page, Integer, in: 1..100, default: 25
    # ...
  end
end
```

- The YARD comment's first line becomes the operation **summary**, the rest its
  **description**.
- Each `param!` call becomes a documented request **parameter** with type and
  constraints.

## 4. Generate

Rake task (runs inside the Rails environment):

```sh
rake openapi:generate
# override output for one run:
rake openapi:generate OUTPUT=tmp/openapi.yaml FORMAT=yaml
```

Or the CLI:

```sh
rails-openapi-generator --rails-root . --output doc/openapi.json
```

## 5. Read the report

Both paths print a summary:

```text
OpenAPI document written to doc/openapi.json
  Processed: 42 endpoints
  Skipped:   1 (GET /legacy → no backing controller action)
  Warnings:  1 (Api::ReportsController#export → non-literal param! arguments)
```

## 6. Validation expectations

- The generated file always validates against the OpenAPI 3.1 meta-schema.
- Re-running with no source changes produces a byte-identical file — safe to
  commit and diff.

## Acceptance smoke test

| Spec story | Quickstart step proving it |
|------------|----------------------------|
| US1 — generate for all endpoints | Step 4 produces a document with one operation per route |
| US2 — parameters from validations | Step 3 `param!` calls appear as typed parameters |
| US3 — titles/descriptions from comments | Step 3 YARD comment becomes summary/description |
