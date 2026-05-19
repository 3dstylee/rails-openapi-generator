# Contract: Source-Path Exclusion Output

How `exclude_source_paths` affects the generated document and the run report.
There is **no new output shape** — excluded endpoints are simply absent, and
reported as skipped.

## Configuration

```ruby
RailsOpenapiGenerator.configure do |config|
  config.exclude_source_paths = [
    "vendor/",                       # substring match
    %r{app/controllers/legacy/}      # regexp match
  ]
end
```

- A `String` entry matches when it is a substring of a controller's resolved
  source file path.
- A `Regexp` entry matches when it matches that path.
- Default: `[]` — nothing is excluded.

An `exclude_source_paths` that is not an Array, or that contains an entry which
is neither a String nor a Regexp, raises `ConfigurationError` before generation.

## Effect on the document

An endpoint whose controller source file path matches any entry is **omitted**
from `paths` entirely — no operation, no parameters, no response. Endpoints
whose source path matches nothing are documented exactly as before.

## Effect on the run report

Each excluded endpoint is listed in the existing `Skipped:` section, with a
reason naming the source-path exclusion:

```text
OpenAPI document written to doc/openapi.json
  Processed:      318 endpoints
  Skipped:        42
    - GET /vendored/widgets (controller source excluded by exclude_source_paths)
    - …
```

## Interaction with `route_filter`

`exclude_source_paths` and the existing `route_filter` are independent and both
apply: a route is excluded if `route_filter` rejects it **or** its controller
source path matches `exclude_source_paths`.

## Unaffected cases

- A route whose controller source file cannot be located is **not** subject to
  source-path exclusion (it has no path to match); it keeps its current
  behavior.
- With `exclude_source_paths` empty/unset, the generated document is identical
  to the pre-feature output.

## Guarantees

- Deterministic output; the document still validates against the OpenAPI 3.1
  schema (FR-009).
- No controller action is executed.
