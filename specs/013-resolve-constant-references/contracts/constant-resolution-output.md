# Contract: Constant Resolution Output

The generator is a library (Ruby gem) + CLI + Rake task that emits an
OpenAPI 3.1 document. This feature changes the documented parameter
schemas for `param!` calls whose argument values reference Ruby
constants — when those constants resolve to schema-compatible values.

## Input — Rails controller action

The motivating shape (from the user's bug report):

```ruby
module AutoPhotoVhs
  class EnqueueFurnitureGenerationService
    MOODS = %w[modern classic minimalist scandinavian industrial].freeze
  end
end

class Api::Player::AutoPhotoVhsController < ApplicationController
  def execute
    param! :mood, String, required: false,
                  in: AutoPhotoVhs::EnqueueFurnitureGenerationService::MOODS

    param! :moods, Array, required: false, default: [] do |p, i|
      p.param! i, String, required: true,
                          in: AutoPhotoVhs::EnqueueFurnitureGenerationService::MOODS
    end

    # ...
  end
end
```

## Output — OpenAPI 3.1 parameter / request-body schemas

For the top-level `param! :mood, ..., in: ...::MOODS` (a non-body
HTTP method would emit it as a query parameter; a POST/PUT/PATCH
emits it inside the `requestBody`):

```yaml
parameters:
  - name: mood
    in: query
    required: false
    schema:
      type: string
      enum:
        - modern
        - classic
        - minimalist
        - scandinavian
        - industrial
```

For the nested `param! :moods, Array do |p, i| p.param! i, String,
in: ...::MOODS end` (request body, since the route is POST):

```yaml
requestBody:
  content:
    application/json:
      schema:
        type: object
        properties:
          moods:
            type: array
            items:
              type: string
              enum:
                - modern
                - classic
                - minimalist
                - scandinavian
                - industrial
```

Notes:
- The `enum` list order matches the constant's value order — no
  re-sorting.
- The `mood` parameter is NOT marked as having unresolved
  arguments — `fully_resolved` is true because the constant
  resolved to a schema-compatible value.
- The "non-literal param! arguments for mood" warning is NOT
  emitted for this parameter.

## Other constant-value shapes

For `param! :page, Integer, in: PaginationLimits::PAGE_RANGE` where
`PAGE_RANGE = 1..100`:

```yaml
- name: page
  in: query
  required: false
  schema:
    type: integer
    minimum: 1
    maximum: 100
```

For `param! :email, String, format: AccountSettings::EMAIL_PATTERN`
where `EMAIL_PATTERN = /\A[^@\s]+@[^@\s]+\z/`:

```yaml
- name: email
  in: query
  required: false
  schema:
    type: string
    pattern: '\A[^@\s]+@[^@\s]+\z'
```

## When the constant cannot be resolved

For `param! :x, String, in: NotALoadableConstant`:

- The generator catches the `NameError` silently.
- The `x` parameter is still documented (name + type + required),
  but without the `enum` constraint.
- The existing warning "non-literal param! arguments for x" fires
  for that route — identical to today's behavior.

For `param! :x, String, in: SomeNonSchemaCompatibleConstant` where
the constant's value is, say, an Array of model instances:

- The constant resolves, but `schema_compatible?` rejects it.
- Treated as if the constant could not be loaded — same fallback
  behavior.

## CLI / Rake / Library parity

No public method signature on `RailsOpenapiGenerator`, no CLI flag,
no Rake task signature, and no configuration key is added or
changed. The CLI, Rake task, and library API all benefit from
constant resolution through the shared `Generator` (Constitution
Principle IV).

## Warning channel

| Action shape | Pre-0.12.0 | After |
|--------------|------------|-------|
| `param!` with `in: Mod::SCHEMA_COMPATIBLE_CONST` | "non-literal param! arguments" warning + missing `enum` | enum populated, no warning |
| `param!` with `in: Mod::UNRESOLVABLE_CONST` | "non-literal param! arguments" warning + missing `enum` | unchanged |
| `param!` with `in: Mod::NON_SCHEMA_COMPATIBLE_CONST` (e.g. Array of class instances) | warning + missing `enum` | unchanged |
| `param!` with fully literal args | byte-identical | byte-identical (SC-004) |

## Determinism & validation

For unchanged host code, repeated runs produce byte-identical
output, including the `enum` list order (matches the constant's
order, which is stable in Ruby). The emitted document continues
to pass OpenAPI 3.1 schema validation; the `enum` array contains
only JSON-serializable primitives by construction (the
schema-compatibility check enforces this).

## Backward compatibility

Operations whose `param!` calls had no constant references in
`0.11.0` emit byte-identical output (SC-004). Operations whose
`param!` calls referenced previously-unresolvable constants gain
the `enum` / `minimum`/`maximum` / `pattern` constraint that
matches the constant's actual value. The change is released as
a MINOR version bump (0.12.0) with a CHANGELOG entry.

## Out of scope (FR-009)

- Constant references outside `param!` calls — `redirect_to
  Routes::ADMIN_INDEX`, `render template: Templates::FALLBACK`,
  etc. A future feature can lift the scope.
- Constants assigned inside controller actions
  (`SOMETHING = compute_at_runtime`).
- Constants resolved through a method chain
  (`Service.new.MOODS` — that's not a constant reference).
- Constants whose value depends on per-request state (none such
  exists in Ruby — constants are not per-request).
