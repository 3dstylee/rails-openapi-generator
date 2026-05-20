# Contract: Template-Render Output

The generator is a library (Ruby gem) + CLI + Rake task that emits an
OpenAPI 3.1 document. This feature changes the documented response set
for operations whose reachable code (action body, helpers,
`before_action` callbacks) contains a template render — `render
"path"`, `render :symbol`, `render template:`, or `render action:`.

## Input — Rails controller action

The motivating shape (from the user's bug report):

```ruby
class Api::V2::Workflow::CustomMaisokusController < ApplicationController
  include AuthCallback # before_action :authenticate (401 render)

  # Update a project from a home staging order item
  # PUT /api/v2/workflow/home_staging_order_items/projects/:id
  def update
    return render_error unless order_item.closing?

    HomeStaging::ProjectService.new.update_project(order_item, params[:selection])
    render_order
  end

  private

  def render_order
    @home_staging_order = order_item.home_staging_order
    render "api/v2/workflow/home_staging_orders/show", formats: :json, handlers: [:jbuilder]
  end

  def render_error
    render json: { message: "..." }, status: :conflict
  end
end
```

Assume `app/views/api/v2/workflow/home_staging_orders/show.json.jbuilder`
exists and produces a schema with (say) `id`, `status`, and
`assignments` keys.

## Output — OpenAPI 3.1 operation responses

```yaml
paths:
  /api/v2/workflow/home_staging_order_items/projects/{id}:
    put:
      operationId: put_api_v2_workflow_home_staging_order_items_projects_id
      responses:
        '200':
          description: Successful response
          content:
            application/json:
              schema:
                type: object
                properties:
                  assignments:
                    type: array
                    items: {}
                  id:
                    type: integer
                  status:
                    type: string
        '401':
          description: Successful response
          content:
            application/json:
              schema:
                type: object
                properties:
                  error:
                    type: string
        '409':
          description: Successful response
          content:
            application/json:
              schema:
                type: object
                properties:
                  message:
                    type: string
```

Notes:
- `200` is contributed by `render_order`'s template render
  (`render "api/v2/workflow/home_staging_orders/show", formats: :json`).
  Its body is the jbuilder schema. The `200` is the HTTP-method
  convention for a `PUT` (no explicit `status:` option on the
  template render).
- `401` is contributed by the concern-included `authenticate` callback
  (feature 010 US3).
- `409` is contributed by the action body's `render_error` helper
  (feature 010 US2).
- No `"response shape could not be determined"` warning is emitted
  for this operation — every status has a known shape (the 200 has a
  literal jbuilder schema; the 401 and 409 have literal hash schemas).

## CLI / Rake / Library parity

No public method signature on `RailsOpenapiGenerator`, no CLI flag, no
Rake task signature, and no configuration key is added or changed. The
CLI, Rake task, and library API all emit the same multi-status,
template-resolved responses for the same controller input
(Constitution Principle IV).

## Warning channel (`stderr` / `GenerationReport.warnings`)

| Action shape | 0.9.0 | After |
|--------------|-------|-------|
| Helper template render + JSON error render | Single entry for the error status (template render dropped); no warning. | Two entries (200 from template + error status from JSON render); no warning. |
| Helper template render only, JSON view exists | (the helper render is dropped, falls through to undeterminable / view) | One entry under the convention status with the jbuilder schema. |
| Helper template render with `formats: :json`, no `.json.jbuilder` exists | (silent drop) | One entry under the convention status, no body. |
| Action-body template render, no helpers (existing case) | Single entry (HTML page or jbuilder) | Byte-identical (SC-004). |
| No render anywhere | Single entry, undeterminable, warning fires | Unchanged. |

## Determinism & validation

For unchanged input, repeated runs MUST produce byte-identical output.
The emitted document MUST continue to pass OpenAPI 3.1 schema validation
with the new template-resolved entries present.

## Backward compatibility

Operations whose only render in 0.9.0 was a single template render at
the convention status — single-page HTML, single-action jbuilder JSON —
emit byte-identical output to 0.9.0 (SC-004). The change is released
as a MINOR version bump (0.10.0) with a CHANGELOG entry (Constitution
Principle V).

## Out of scope (FR-009)

- `respond_to { |format| format.json { render ... } }` blocks.
- Renders dispatched dynamically (`send(name)`, `public_send(name)`).
- Non-literal `formats:` values (procs, instance variables, method
  calls).
- `render partial:` (a partial is not a complete response).
- Bare-status-symbol renders (`render :ok`) — today's
  "treat-as-template-name" behavior remains.
- `rescue_from` handlers (already deferred by feature 010 FR-009).
