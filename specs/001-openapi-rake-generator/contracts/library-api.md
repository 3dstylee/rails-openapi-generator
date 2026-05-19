# Contract: Library API

The public Ruby surface of the gem. The rake task and the CLI are both thin
wrappers over this API (Constitution IV) — they MUST NOT contain generation
logic.

## `RailsOpenapiGenerator.configure { |config| ... }`

Yields a `Configuration` for the host app to set defaults (typically in an
initializer).

```ruby
RailsOpenapiGenerator.configure do |config|
  config.output_path = "doc/openapi.yaml"
  config.title       = "My API"
  config.api_version = "2.3.0"
  config.route_filter = ->(route) { route.path.start_with?("/api/") }
end
```

## `RailsOpenapiGenerator::Configuration`

| Attribute | Type | Default |
|-----------|------|---------|
| `output_path` | String | `"doc/openapi.json"` |
| `format` | Symbol (`:json` / `:yaml`) | inferred from `output_path` |
| `route_filter` | `#call(Route) -> Boolean` | accepts all |
| `title` | String | host application name |
| `api_version` | String | `"1.0.0"` |

Invalid configuration (unwritable `output_path`, unknown `format`) raises
`RailsOpenapiGenerator::ConfigurationError` before any work begins.

## `RailsOpenapiGenerator::Generator`

```ruby
generator = RailsOpenapiGenerator::Generator.new(configuration)
report    = generator.generate
```

### `#new(configuration = RailsOpenapiGenerator.configuration)`

Builds a generator bound to a `Configuration`.

### `#generate -> GenerationReport`

Runs the full pipeline (data-model.md), writes the OpenAPI document to
`configuration.output_path`, and returns a `GenerationReport`.

**Guarantees**:
- MUST NOT execute any host controller action or mutate host app state (FR-015).
- MUST write a document that validates against the OpenAPI 3.1 meta-schema
  (FR-005), even when zero routes match (empty `paths`).
- MUST include every resolvable endpoint (FR-004, FR-011).
- MUST continue past a single failing endpoint, recording a warning (FR-016).
- MUST produce byte-identical output for unchanged input (SC-008).

### `#document -> Hash`

Returns the assembled `OpenApiDocument` as a Hash without writing a file
(useful for tests and programmatic consumers).

## `RailsOpenapiGenerator::GenerationReport`

Read-only result object.

| Method | Returns |
|--------|---------|
| `#processed_count` | Integer |
| `#skipped` | Array of `{ route:, reason: }` |
| `#warnings` | Array of String |
| `#output_path` | String |
| `#success?` | Boolean — true (run completes even with warnings) |

## Error contract

| Condition | Behavior |
|-----------|----------|
| Invalid configuration | raise `ConfigurationError` (before generation) |
| Route with no backing action | skip, add to `report.skipped` with reason |
| Unparseable comment / non-literal `param!` | warning in `report.warnings`, endpoint still emitted |
| Output directory unwritable | raise `ConfigurationError` |

Generation never raises for per-endpoint analysis problems — those degrade to
warnings (FR-016).
