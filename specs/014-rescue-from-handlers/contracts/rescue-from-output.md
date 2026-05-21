# Contract: rescue_from Handler Output

The generator emits an OpenAPI 3.1 document. This feature adds
response entries to operations whose controller class chain
contains one or more `rescue_from` declarations. The shape of the
added entries comes from each handler's render call(s).

## Input — Rails controller hierarchy

```ruby
class ApplicationController < ActionController::API
  rescue_from ActiveRecord::RecordNotFound, with: :record_not_found
  rescue_from Pundit::NotAuthorizedError, with: :forbidden
  rescue_from ActionController::ParameterMissing, with: :bad_request

  private

  def record_not_found
    render json: { error: "not_found" }, status: :not_found
  end

  def forbidden
    render json: { error: "forbidden" }, status: :forbidden
  end

  def bad_request(exception)
    render json: { error: exception.message }, status: :bad_request
  end
end

class Api::FoosController < ApplicationController
  def show
    @foo = Foo.find(params[:id])
    authorize @foo
    render json: @foo.as_json
  end
end
```

## Output — OpenAPI 3.1 operation responses

```yaml
paths:
  /api/foos/{id}:
    get:
      operationId: get_api_foos_id
      responses:
        '200':
          description: Successful response
          content:
            application/json:
              schema:
                # ... whatever Foo#as_json statically resolves to ...
        '400':
          description: Successful response
          content:
            application/json:
              schema:
                type: object
                properties:
                  error:
                    type: string
        '403':
          description: Successful response
          content:
            application/json:
              schema:
                type: object
                properties:
                  error:
                    type: string
        '404':
          description: Successful response
          content:
            application/json:
              schema:
                type: object
                properties:
                  error:
                    type: string
```

Notes:
- The `400`, `403`, `404` entries come from the rescue_from
  handlers' renders. Every action on every controller inheriting
  from `ApplicationController` gains these entries.
- The `200` entry comes from the action's own render.
- The handler's literal body shape (the `{ error: "string" }` schema)
  is documented. Non-literal values (`exception.message`) resolve
  to the permissive `{}` schema (today's behavior).
- No "non-literal param! arguments" warning fires for any of these.
- Content types and status keys are sorted alphabetically (existing
  determinism rule).

## Block-form handler

```ruby
class Api::BarsController < ApplicationController
  rescue_from ActiveRecord::RecordInvalid do |error|
    render json: { errors: error.record.errors }, status: :unprocessable_entity
  end
end
```

```yaml
'422':
  description: Successful response
  content:
    application/json:
      schema:
        type: object
        properties:
          errors: {}
```

## Same-status collision (action body + handler)

If the action body does `render json: { id: 1 }, status: :not_found`
and the rescue_from handler also does
`render json: { error: "..." }, status: :not_found`:

```yaml
'404':
  description: Successful response
  content:
    application/json:
      schema:
        oneOf:
          - type: object
            properties:
              error:
                type: string
          - type: object
            properties:
              id:
                type: integer
```

(Sorted by canonical JSON for determinism, per feature 010 R2.)

## CLI / Rake / Library parity

No public method signature, no CLI flag, no Rake task signature,
no configuration key added. CLI / Rake / library all gain the
same coverage through the shared `Generator` (Constitution
Principle IV).

## Warning channel

| Action shape | Pre-0.14.0 | After |
|--------------|------------|-------|
| Action that emits 404 only via `rescue_from RecordNotFound` | "response shape could not be determined" if no other render | the 404 entry from the handler is documented; warning behavior unchanged for OTHER triggers |
| Handler whose method can't be resolved (gem code) | invisible | silently skipped; no new warning |
| Handler with non-literal `status:` | invisible | site dropped per existing rule; no new warning |
| Re-raising handler | invisible | invisible (no rendering happens before the raise) |
| Action whose controller has no `rescue_from` on the chain | byte-identical | byte-identical (SC-004) |

A rescue_from-derived site MUST NOT add new warning categories.

## Determinism & validation

For unchanged host code, repeated runs produce byte-identical
output. The handler bodies are walked deterministically; the
per-status union sorts schemas by canonical JSON; content types
sort alphabetically. The emitted document continues to pass
OpenAPI 3.1 schema validation.

## Backward compatibility

Operations on controllers whose entire class chain has no
`rescue_from` declarations emit byte-identical output (SC-004).
Released as a MINOR version bump (0.14.0).

## Out of scope (FR-009, Edge Cases)

- Re-raising handlers (`raise OtherError`)
- Handlers that delegate to `Rails.error.handle` /
  `ActiveSupport::ErrorReporter`
- Non-literal status values from the rescued exception
- Exception-implied statuses without an explicit `rescue_from`
- Surfacing the rescued exception class name in the OpenAPI doc
  (the doc names the status, not the trigger)
