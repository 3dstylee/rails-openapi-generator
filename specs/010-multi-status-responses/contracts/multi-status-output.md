# Contract: Multi-Status Output

The generator is a library (Ruby gem) + CLI + Rake task that emits an
OpenAPI 3.1 document. This feature changes the shape of an operation's
`responses` map for JSON-shaped operations whose action (or its helpers
or before_action callbacks) issues more than one render at distinct
HTTP statuses.

## Input — Rails controller action

Any controller action whose reachable code (action body + receiverless
helper methods + `before_action` callbacks) contains more than one
distinct `render json:` status, or one render plus one or more `head`
calls.

### Motivating example

```ruby
# app/controllers/concerns/auth_callback.rb
module AuthCallback
  extend ActiveSupport::Concern
  included do
    before_action :authenticate
  end

  private

  def authenticate
    return if current_user

    render json: { error: "unauthorized" }, status: :unauthorized
  end
end

# app/controllers/api/v2/workflow/custom_maisokus_controller.rb
class Api::V2::Workflow::CustomMaisokusController < ApplicationController
  include AuthCallback

  def update
    custom_maisoku = authorize policy_scope(CustomMaisoku).find(params[:id])
    error_messages = ::CustomMaisokuContext::UpsertService.update(
      custom_maisoku, current_user, custom_maisoku_params
    )

    if error_messages.blank?
      send_custom_maisoku_log(custom_maisoku, "update")
      render json: publish_file_urls(custom_maisoku)
    else
      render json: { error_messages: error_messages }, status: :unprocessable_entity
    end
  end
end
```

## Output — OpenAPI 3.1 operation responses

```yaml
paths:
  /api/v2/workflow/custom_maisokus/{id}:
    patch:
      operationId: patch_api_v2_workflow_custom_maisokus_id
      responses:
        '200':
          description: Successful response
        '401':
          description: Successful response
          content:
            application/json:
              schema:
                type: object
                properties:
                  error:
                    type: string
        '422':
          description: Successful response
```

Notes:
- `200` has no `content` because `publish_file_urls(custom_maisoku)` is a
  method call (non-literal).
- `401` has a known schema because the concern's `authenticate` does a
  literal `render json: { error: "unauthorized" }, ...`.
- `422` has no `content` because `error_messages` is a variable
  (non-literal).
- No `"response shape could not be determined"` warning is emitted for
  this operation — every documented status is statically known.

### Same-status union

For an action containing both:

```ruby
render json: { id: 1, name: "x" }
render json: { id: 2 }
```

(both at the same status), the entry body is:

```yaml
'200':
  description: Successful response
  content:
    application/json:
      schema:
        oneOf:
          - type: object
            properties:
              id:
                type: integer
          - type: object
            properties:
              id:
                type: integer
              name:
                type: string
```

The `oneOf` list is sorted by canonical JSON ascending for determinism.

### Head + render collapse

For `head :ok` and `render json: { id: 1 }, status: :ok` in the same
action, the entry at `200` has the render's body (FR-005); no `oneOf` is
emitted and `head`'s no-body contribution is dropped.

## CLI / Rake / Library parity

No public method signature on `RailsOpenapiGenerator`, no CLI flag, no
Rake task signature, and no configuration key is added or changed. The
CLI, Rake task, and library API all emit the same multi-status responses
for the same controller input (Constitution Principle IV).

## Warning channel (`stderr` / `GenerationReport.warnings`)

| Action shape | Today | After |
|--------------|-------|-------|
| Happy `render json:` only, literal body | (no warning) | (no warning — unchanged output) |
| Happy `render json:` only, non-literal body, no view | `<method> <path>: response shape could not be determined` | (no warning) — entry under the convention status, no body |
| Happy + error renders, both non-literal | warning fires (happy entry only) | (no warning) — two entries, both body-less |
| No render, no head, no redirect, no view | warning fires | warning fires (unchanged) |
| Redirect / file_download / html_page | (no warning) | (no warning — unchanged) |

A multi-status classification MUST NOT add new warning messages.

## Determinism & validation

For unchanged input, repeated runs MUST produce byte-identical output —
including `oneOf` lists, which are sorted by canonical JSON.
The emitted document MUST continue to pass OpenAPI 3.1 schema validation
when one or more multi-status responses are present.

## Backward compatibility

Operations whose action contains exactly one `render json:` (and no
helper or before_action renders) emit byte-identical output to `0.8.0`
(SC-005). The change is released as a MINOR version bump (0.9.0) with a
CHANGELOG entry (Constitution Principle V).

## Out of scope (FR-009)

- `rescue_from` handler renders.
- Statuses implied by exception-raising calls (Pundit `authorize` →
  `Pundit::NotAuthorizedError` → handler in ApplicationController;
  ActiveRecord `find` → `RecordNotFound`; etc.).
- Dynamically dispatched callbacks (`before_action proc { ... }`
  inline blocks; `before_action`s with non-literal symbols).
