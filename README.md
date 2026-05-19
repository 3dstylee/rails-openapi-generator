# rails-openapi-generator

Generate a single OpenAPI 3.1 document for a Rails application straight from
what your code already declares:

- **Endpoints** are discovered from the Rails route set.
- **Request parameters** are derived from your existing
  [`rails_param`](https://github.com/nicolasblanco/rails_param) `param!`
  declarations — types, required flags, and constraints.
- **Operation summaries and descriptions** are taken from the YARD comment above
  each controller action.

Generation runs as a rake task (or an equivalent CLI) and never executes your
controller actions — everything is read by static source analysis.

## Installation

Add the gem to your application's `Gemfile`:

```ruby
gem "rails-openapi-generator"
```

Then install:

```sh
bundle install
```

The gem's railtie registers the `openapi:generate` rake task automatically — no
`Rakefile` change is needed.

## Configuration

Configuration is optional. To override the defaults, create
`config/initializers/rails_openapi_generator.rb`:

```ruby
RailsOpenapiGenerator.configure do |config|
  config.output_path  = "doc/openapi.yaml"          # default: doc/openapi.json
  config.title        = "My Store API"              # default: the app name
  config.api_version  = "2.0.0"                      # default: "1.0.0"
  config.route_filter = ->(route) { route.path.start_with?("/api/") }
end
```

| Setting | Default | Description |
|---------|---------|-------------|
| `output_path` | `doc/openapi.json` | Destination file. |
| `format` | inferred from `output_path` | `:json` or `:yaml`. |
| `title` | host application name | Document `info.title`. |
| `api_version` | `"1.0.0"` | Document `info.version`. |
| `route_filter` | include all | A callable `(Route) -> Boolean` selecting routes. |

## Documenting endpoints

If you already use `rails_param` and YARD comments, there is nothing extra to
write:

```ruby
class Api::UsersController < ApplicationController
  # Search users
  # Returns the users matching the given filters, newest first.
  def index
    param! :query,    String,  blank: false
    param! :per_page, Integer, in: 1..100
    # ...
  end
end
```

- The first comment line becomes the operation **summary**; the rest becomes the
  **description**.
- Each `param!` call becomes a documented request **parameter** with its type
  and constraints. For `GET`/`DELETE` these are query parameters; for
  `POST`/`PUT`/`PATCH` they form a JSON request body. Dynamic route segments
  (`:id`) become path parameters.

Every operation is also **tagged with its controller class name** (e.g.
`Api::UsersController`), and the document lists those tags at the top level.
OpenAPI viewers such as Redoc and Swagger UI use tags to group operations into
per-controller sections in the sidebar — no extra setup required.

Each operation's **description ends with a reference to the source file and
line** of the action (e.g. `Source: app/controllers/api/users_controller.rb:12`),
so readers can jump straight from the docs to the implementation.

## Generating the document

Via the rake task (runs inside the Rails environment):

```sh
rake openapi:generate

# override the output for a single run:
rake openapi:generate OUTPUT=tmp/openapi.yaml FORMAT=yaml
```

Via the CLI:

```sh
rails-openapi-generator --rails-root . --output doc/openapi.json
```

Both print a run summary:

```text
OpenAPI document written to doc/openapi.json
  Processed: 42 endpoints
  Skipped:   1
    - GET /legacy (no backing controller action)
  Warnings:  0
```

## Previewing the document in a browser

The generated file is a standard OpenAPI document, so any OpenAPI viewer can
render it. A quick option using [Redocly CLI](https://github.com/Redocly/redocly-cli)
(needs Node.js) — `build-docs` inlines the spec into a self-contained HTML file
that opens directly, no server required:

```sh
npx @redocly/cli build-docs doc/openapi.json -o doc/openapi.html
open doc/openapi.html
```

Re-run that after each `openapi:generate`. Other viewers:

- **Swagger UI via Docker** (interactive "Try it out"):

  ```sh
  docker run --rm -p 8081:8080 \
    -e SWAGGER_JSON=/spec/openapi.json \
    -v "$PWD/doc:/spec" \
    swaggerapi/swagger-ui
  # open http://localhost:8081
  ```

- **VS Code**: the "OpenAPI (Swagger) Editor" extension renders a preview pane
  when you open the document.

## Guarantees

- The generated document validates against the OpenAPI 3.1 schema.
- Re-running with no source changes produces a byte-identical file — safe to
  commit and diff.
- A route that cannot be fully analyzed produces a warning; the run still
  completes and every other endpoint is still included.

## Programmatic use

The rake task and CLI are thin wrappers over the library API:

```ruby
config = RailsOpenapiGenerator::Configuration.new
config.output_path = "doc/openapi.json"

report = RailsOpenapiGenerator::Generator.new(config).generate
report.processed_count # => 42

# Or build the document Hash without writing a file:
document = RailsOpenapiGenerator::Generator.new(config).document
```

## Development

```sh
bundle install
bundle exec rspec
bundle exec rubocop
```

## License

Released under the MIT License.
