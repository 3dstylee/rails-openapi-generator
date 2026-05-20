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
| `exclude_source_paths` | `[]` | Strings/regexps; endpoints whose controller source file path matches are excluded. |
| `method_resolution_depth` | `5` | How deep wrapper/helper method chains are followed. |

`route_filter` filters by route; `exclude_source_paths` filters by **where the
controller is defined** — handy for dropping vendored or third-party controllers:

```ruby
RailsOpenapiGenerator.configure do |config|
  config.exclude_source_paths = ["vendor/", %r{app/controllers/legacy/}]
end
```

A string entry matches as a substring of the controller's source file path; a
regexp entry matches the path. Excluded endpoints are listed in the run report's
`Skipped:` section. Both filters apply — an endpoint is excluded if either drops
it.

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
- Parameters used **implicitly** — `params[:key]`, `params.require`,
  `params.permit`, `params.fetch`, `params.dig` — are detected too, in the
  action and recursively in the helper methods it calls. They are documented
  with a permissive ("any") schema. A key already declared via `param!` or as a
  path parameter keeps its richer definition; Rails-internal keys
  (`controller`, `action`, `format`) are skipped.

Every operation is also **tagged with its controller class name** (e.g.
`Api::UsersController`), and the document lists those tags at the top level.
OpenAPI viewers such as Redoc and Swagger UI use tags to group operations into
per-controller sections in the sidebar — no extra setup required.

Each operation's **description ends with a reference to the source file and
line** of the action (e.g. `Source: app/controllers/api/users_controller.rb:12`),
so readers can jump straight from the docs to the implementation.

## Response bodies

Each operation's success response carries a body schema, derived by static
inspection of two sources:

- **jbuilder view templates** — the `.json.jbuilder` the action renders, located
  by Rails view conventions (`app/views/<controller>/<action>.json.jbuilder`).
  `json.array!` becomes an array schema, `json.partial!` is followed, nested
  `json.x do … end` blocks become nested objects.
- **literal `render json:`** — an inline `render json: { … }` with literal
  values. A literal render takes precedence over a view template.

Field **names and nesting** are always recovered. Field **types** are
best-effort: typed when read from a literal, permissive (`{}`, meaning "any")
when read from a jbuilder value expression such as `json.name user.name`.

Each operation's success response is filed under the status code the action
**explicitly sets** — read from `head :symbol` / `head <integer>` calls and the
`status:` option of `render` calls (e.g. `head :ok` → 200,
`render json: x, status: :created` → 201). A `head` response is documented with
no body. When an action sets no explicit status, the HTTP-method convention
applies:

| Endpoint kind | Convention status |
|---------------|-------------------|
| Reads / updates (GET, PUT, PATCH) | 200 |
| Creation (POST) | 201 |
| Deletion (DELETE) | 204 (no body) |

Only happy-path (2xx/3xx) statuses are read; an error-status guard
(`render status: :unprocessable_entity`) does not affect the documented success
status.

`rescue_from` declarations on the controller class chain are detected
and each handler's renders are documented as response entries on every
action in the controller. An `ApplicationController` declaring
`rescue_from RecordNotFound, with: :record_not_found` (rendering 404
with a literal body) adds a `404` entry to every inheriting
controller's operations. Method-form (`with: :method`) and block-form
(`rescue_from FooError do |e| ... end`) handlers are both walked.
Handlers declared in concerns are picked up via the `rescue_handlers`
chain. Handlers whose method cannot be resolved (defined in a gem,
for example) are silently skipped. Controllers without any
`rescue_from` declarations on their entire ancestor chain emit
byte-identical output to before the feature.

An action whose success path is `redirect_to` (or `redirect_back` /
`redirect_back_or_to`) is documented as a redirect: the response is filed under
the call's 3xx status (`302` by default, or the `status:` option — e.g.
`redirect_to path, status: :see_other` → `303`) with no response body. JSON
renders, file downloads, inline HTML, and resolvable view templates continue to
take precedence over a redirect signal.

For JSON operations, **every** `render json:` and `head` call reachable from
the action is documented — not only the happy path. An action with both a
happy `render json: ...` and a guard
`render json: { ... }, status: :unprocessable_entity` produces two response
entries (e.g. `200` and `422`), each with the schema of the corresponding
render (or no body when the render's argument is a non-literal). Renders
reached through helper methods (including methods in concerns mixed into the
controller) and through `before_action` callbacks contribute to the response
set the same way. `before_action` filters with a literal `only: [...]` /
`except: [...]` are honored; non-literal conditionals fall back to "applies
to every action in this controller". `rescue_from` handlers and statuses
implied by exception-raising calls (Pundit `authorize`, ActiveRecord
`find!`) are out of scope.

When two renders share a status with distinct literal shapes, the entry's
body becomes an OpenAPI `oneOf` of the unique schemas, sorted by canonical
JSON for determinism.

Template renders — `render "path/to/template"`, `render :symbol`,
`render template:`, `render action:` — are also collected from helpers and
`before_action` callbacks. An explicit `formats:` option chooses which view
to resolve: `formats: :json` looks up `.json.jbuilder`, `formats: :html`
looks up `.html.*`, and a literal array tries each in order. When the
option is absent or non-literal, the default "prefer JSON over HTML"
lookup applies. When the requested view does not exist, the operation gets
a body-less entry under the status (the status is known, the body is not).
An action whose only renders are HTML-template renders at a single status
classifies as an HTML page (single-entry, `text/html`) — even when the
render lives in a helper.

`respond_to do |format| ... end` blocks are detected too. Each
`format.json` gate adds an `application/json` content (schema from the
default `.json.jbuilder` or from an inline render), each `format.html`
gate adds a `text/html` content (default `.html.*` or inline render).
When both apply at the same status, the response carries both content
types under one OpenAPI entry:

```yaml
'200':
  description: Successful response
  content:
    application/json: { schema: { ... } }
    text/html:        { schema: { type: string } }
```

Only `:json` and `:html` format symbols are mapped in v1. `format.xml`,
`format.csv`, `format.any`, `format.all`, and dynamic dispatch are
silently ignored.

Constants used as `param!` argument values are resolved at generation
time. `param! :mood, String, in: Module::CONSTANT` documents the
parameter's `enum` from the constant's actual value when that value
is schema-compatible — an Array of primitives, a Range (`minimum`/
`maximum`), a Regexp (`pattern`), a primitive, or a recursively-
checked Hash. Lookup uses `Object.const_get(name, true)` with
autoload, results are cached per generator run, and any lookup
failure (`NameError`, `LoadError`) is silently treated as
unresolved — the generator never raises because of this feature.
Bare (`FOO`), qualified (`A::B::C`), and top-level (`::Foo`)
constant references are all supported. Constants referenced
outside `param!` calls (in `render`, `redirect_to`, `respond_to`,
etc.) are out of scope in v1.

Endpoints whose response shape cannot be determined (non-literal `render json:`,
serializer-based responses, unlocatable partials) still get a valid success
response with no body schema, and are named in the run report. No controller
action is executed — everything is read statically. Error responses (4xx/5xx)
are out of scope.

## HTML pages & file downloads

Not every route serves JSON. The generator classifies each action and marks the
ones that don't:

- **HTML page** — an action that renders an HTML view (explicitly via
  `render template:`/`render :action`/`render html:`, or implicitly when its
  only view is a `.html.*` file). Its success response is `text/html`, it gains
  an `"HTML Pages"` tag and an `x-renders-html` extension, and its description
  notes the template.
- **File download** — an action that calls `send_file` / `send_data`. Its
  success response is `application/octet-stream`, it gains a `"File Downloads"`
  tag and an `x-sends-file` extension.

A `render json:` always wins — a JSON endpoint is never marked as a page or
download, and JSON-endpoint output is unchanged. Redoc/Swagger UI show "HTML
Pages" and "File Downloads" as their own sidebar sections, and the run report
counts both.

File-download detection also resolves **wrapper methods**: if an action streams
a file through a helper (e.g. `send_file_and_cleanup`) instead of calling
`send_file`/`send_data` directly, the generator follows that helper to its
definition — in the controller, an included concern, or a parent controller —
and through chains of wrappers, until it finds the download call. Resolution is
static, cycle-guarded, and bounded by `download_resolution_depth` (default 5):

```ruby
RailsOpenapiGenerator.configure do |config|
  config.download_resolution_depth = 5 # how deep wrapper chains are followed
end
```

```text
  Processed:      626 endpoints
  HTML pages:     128 endpoints
  File downloads: 6 endpoints
```

The `x-renders-html` / `x-sends-file` flags make non-JSON endpoints easy to
filter out of the document with a post-processing step if you want a pure JSON
API spec.

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
rake openapi:generate
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
