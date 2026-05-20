# Contract: Redirect Output

The generator is a library (Ruby gem) + CLI + Rake task that emits an
OpenAPI 3.1 document. The public contract impacted by this feature is the
**generated OpenAPI document for endpoints whose action issues a redirect**.

## Input — Rails controller action

Any controller action whose body contains a happy-path `redirect_to`,
`redirect_back`, or `redirect_back_or_to` call, **and** which does not also
contain a higher-precedence happy-path signal (`render json:`, `send_file`,
`send_data`, inline `render html:`, or a resolvable view template).

### Examples

```ruby
# Bare redirect (defaults to 302).
def create
  parent_folder = ParentFolder.create!(parent_folder_params)
  redirect_to parent_folder
end

# Explicit status by symbol.
def create
  parent_folder = ParentFolder.create!(parent_folder_params)
  redirect_to parent_folder, status: :see_other
end

# Explicit status by integer.
def update
  @resource.update!(resource_params)
  redirect_to @resource, status: 301
end

# redirect_back_or_to (Rails 7+).
def update
  @resource.update!(resource_params)
  redirect_back_or_to root_path
end
```

## Output — OpenAPI 3.1 operation responses

For an action with `redirect_to @parent_folder` and no `status:` option:

```yaml
paths:
  /parent_folders:
    post:
      operationId: post_parent_folders
      description: |-
        _Redirects to another URL._

        _Source: `app/controllers/parent_folders_controller.rb:42`_
      responses:
        '302':
          description: Successful response
```

For an action with `redirect_to path, status: :see_other`:

```yaml
      responses:
        '303':
          description: Successful response
```

### What does NOT appear in the response

- No `content` key (a redirect has no body).
- No `application/json` schema.
- No `text/html` schema.
- No `headers` entry (`Location` is out of scope — research R7).
- The operation has **no** `x-renders-html` / `x-sends-file` / `x-redirects`
  vendor extension (research R9).

## CLI / Rake / Library parity

This feature changes **only** generated document content. No public method
signature on `RailsOpenapiGenerator`, no CLI flag, no Rake task signature,
and no configuration key is added or changed. The CLI, Rake task, and
library API all emit the same redirect response for the same controller
input (Constitution Principle IV).

## Warning channel (`stderr` / `GenerationReport.warnings`)

| Action shape | Today | After |
|--------------|-------|-------|
| `redirect_to` only (no other signals) | `POST /…: response shape could not be determined` | (no warning) |
| `redirect_to` + `render json:` | (no warning) | (no warning — JSON wins, redirect ignored for classification) |
| Action with no render and no redirect | `…: response shape could not be determined` | (unchanged — still emitted) |

A redirect classification **MUST NOT** add new warning messages.

## Determinism & validation

For unchanged input, repeated runs MUST produce byte-identical output. The
emitted document MUST continue to pass OpenAPI 3.1 schema validation when a
redirect response is present.

## Backward compatibility

The change affects only endpoints whose existing documented output was a
status-code mismatch + a spurious "undeterminable" body (e.g. the
`POST /parent_folders` case in the bug report). All other endpoints emit
byte-identical output to today. The change is released as a MINOR version
bump with a CHANGELOG entry (Constitution Principle V).
