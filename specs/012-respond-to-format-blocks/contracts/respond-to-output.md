# Contract: respond_to Format Block Output

The generator is a library (Ruby gem) + CLI + Rake task that emits an
OpenAPI 3.1 document. This feature changes the documented response
set for operations whose reachable code contains a `respond_to
do |format| ... end` block with `format.json` and/or `format.html`
calls.

## Input — Rails controller action

The motivating shape (from the user's example):

```ruby
class Api::ProjectsController < ApplicationController
  def index
    authorize_access_index
    assign_rendering_parameters!(@project)

    respond_to do |format|
      format.html do
        gon.push(gon_params)
      end
      format.json
    end
  end
end
```

Assume `app/views/api/projects/index.html.erb` and
`app/views/api/projects/index.json.jbuilder` both exist; the
jbuilder defines (say) `id`, `name`, and `metadata`.

## Output — OpenAPI 3.1 operation responses

```yaml
paths:
  /api/projects:
    get:
      operationId: get_api_projects
      responses:
        '200':
          description: Successful response
          content:
            application/json:
              schema:
                type: object
                properties:
                  id:
                    type: integer
                  metadata: {}
                  name:
                    type: string
            text/html:
              schema:
                type: string
```

Notes:
- The `200` response carries both `application/json` and `text/html`
  content types — OpenAPI 3.1 supports this natively.
- The `application/json` schema is the parsed jbuilder.
- The `text/html` schema is the today's placeholder `{type: string}`
  (same as feature 003's HTML-page emission).
- Content types are sorted by name ascending — `application/json`
  before `text/html` — for determinism.
- No `"response shape could not be determined"` warning is emitted —
  at least one statically-known content type contributes.

## When only one view exists

```ruby
def index
  respond_to do |format|
    format.html { gon.push(gon_params) }
    format.json   # no view exists
  end
end
```

If `index.html.erb` exists but `index.json.jbuilder` does NOT:

```yaml
'200':
  description: Successful response
  content:
    text/html:
      schema:
        type: string
```

The missing JSON view does not produce an empty `application/json`
entry; it contributes nothing (FR-003).

## Explicit render inside a format block

```ruby
def show
  respond_to do |format|
    format.json { render json: { id: 1, ok: true } }
    format.html # default view
  end
end
```

```yaml
'200':
  description: Successful response
  content:
    application/json:
      schema:
        type: object
        properties:
          id:
            type: integer
          ok:
            type: boolean
    text/html:
      schema:
        type: string
```

The explicit `render json:` schema is used for the
`application/json` entry; the default `.html.erb` is used for the
`text/html` entry.

## Same content type contributed twice

```ruby
def create
  respond_to do |format|
    format.json { render json: { id: 1 } }
  end
  render json: { id: 2 }  # unreachable in practice, but statically present
end
```

The two JSON sites at the same status (201, POST convention) collapse
per feature 010 FR-004: identical schemas dedup; distinct schemas
union into `oneOf`. The above produces a single
`application/json` entry under 201 with `oneOf` of the two unique
shapes.

## CLI / Rake / Library parity

No public method signature on `RailsOpenapiGenerator`, no CLI flag, no
Rake task signature, and no configuration key is added or changed. The
CLI, Rake task, and library API all emit the same multi-content-type
responses for the same controller input (Constitution Principle IV).

## Warning channel

| Action shape | 0.10.0 | After |
|--------------|--------|-------|
| `respond_to { |format| format.html { ... }; format.json }` with both views | (the operation is documented with no content; warning may fire if no other signal) | One entry with both content types; no warning |
| `respond_to { |format| format.json }` with only `.json.jbuilder` | (warning may fire) | One entry with `application/json` content; no warning |
| `respond_to { |format| format.xml }` (unmapped) with no other render | unchanged | unchanged (warning still fires — XML not mapped in v1) |
| Action with no `respond_to` and a single render | byte-identical | byte-identical (SC-004) |

## Determinism & validation

For unchanged input, repeated runs MUST produce byte-identical output
— including content-type ordering within a response (alphabetical) and
schema dedup within a single content type (feature 010 rules). The
emitted document MUST continue to pass OpenAPI 3.1 schema validation
with multi-content-type entries.

## Backward compatibility

Operations that do not use `respond_to` in `0.10.0` emit byte-
identical output to `0.10.0` (SC-004). Operations whose `respond_to`
block contributes only one content type also emit byte-identical
output to "the same action without `respond_to`". The change is
released as a MINOR version bump (0.11.0) with a CHANGELOG entry
(Constitution Principle V).

## Out of scope (FR-008, FR-009)

- `format.xml` / `format.csv` / `format.pdf` / `format.js` / other
  format symbols not in `FORMAT_CONTENT_TYPES`. Silently ignored.
- `format.any` / `format.all` / dynamic dispatch (`format.send(:json)`,
  `formats.each { |fmt| format.public_send(fmt) }`).
- `respond_to` without a block argument (invalid Rails syntax).
- `rescue_from` handlers (deferred since feature 010).
- Exception-implied content types.
