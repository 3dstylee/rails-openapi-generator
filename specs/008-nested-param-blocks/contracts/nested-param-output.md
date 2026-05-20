# Contract: Nested-Parameter-Block Output

The generator is a library (Ruby gem) + CLI + Rake task that emits an
OpenAPI 3.1 document. This feature changes the documented parameter
schemas for `param!` calls of type `Hash` / `Array` that carry a
`do |...| ... end` block declaring nested fields / item shapes.

## Input — Rails controller action

The motivating shape (from the user's report — combined with
feature 013's constant resolution):

```ruby
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

## Output — OpenAPI 3.1 request-body schema

```yaml
requestBody:
  content:
    application/json:
      schema:
        type: object
        properties:
          mood:
            type: string
            enum:
              - modern
              - classic
              - minimalist
              - scandinavian
              - industrial
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
- The flat `mood` parameter is unchanged from feature 013's output.
- The nested-block `moods` parameter is the new shape: an `array`
  whose `items` schema is `string` with the same `enum` resolved
  from the constant.
- The constant resolution inside the nested block uses feature
  013's `ConstantResolver` automatically — no extra wiring.

## Other nested shapes

### Hash with two scalar fields

```ruby
param! :q, Hash do |q|
  q.param! :keyword, String
  q.param! :page,    Integer, in: 1..100
end
```

```yaml
q:
  type: object
  properties:
    keyword:
      type: string
    page:
      type: integer
      minimum: 1
      maximum: 100
```

### Array of objects (nested two levels)

```ruby
param! :items, Array do |a, i|
  a.param! i, Hash do |inner|
    inner.param! :id, Integer, required: true
    inner.param! :name, String
  end
end
```

```yaml
items:
  type: array
  items:
    type: object
    properties:
      id:
        type: integer
      name:
        type: string
```

### Hash with empty block

```ruby
param! :metadata, Hash do |m|
  # No nested param! calls.
end
```

```yaml
metadata:
  type: object
```

(Falls back to bare object — FR-007.)

### Block on a non-Hash/Array type

```ruby
param! :name, String do |s|
  # Ignored — type is not Hash/Array.
end
```

```yaml
name:
  type: string
```

(Block silently ignored — FR-008.)

## CLI / Rake / Library parity

No public method signature on `RailsOpenapiGenerator`, no CLI flag,
no Rake task signature, and no configuration key is added or
changed (the depth bound reuses `method_resolution_depth`). The
CLI, Rake task, and library API all benefit from nested-param-block
detection through the shared `Generator` (Constitution Principle IV).

## Warning channel

| Action shape | Pre-0.13.0 | After |
|--------------|------------|-------|
| `param! :h, Hash do \|q\| q.param! :a, String end` | Documented as bare `object`; no warning | Documented as object with `a` property; no warning |
| `param! :a, Array do \|p, i\| p.param! i, Type, in: Module::CONST end` | Documented as bare `array`; "non-literal param! arguments" warning for the outer `param!` if the outer's args also include unresolved values | Documented as array with `items` schema; same warning behavior on the OUTER param! (unchanged) |
| Nested `param!` with non-literal args | n/a (wasn't walked) | Same "non-literal param! arguments" warning, scoped to the nested parameter name |
| Flat `param!` (no block) | byte-identical | byte-identical (SC-005) |
| Beyond depth bound | n/a (wasn't walked) | Descent stops silently; the over-depth subtree emits a bare object/array; no warning, no exception (FR-005) |

A nested-parameter detection MUST NOT add new warning categories.

## Determinism & validation

For unchanged host code, repeated runs produce byte-identical
output. Nested `properties:` are sorted alphabetically (matching
the existing flat-property sort), and the document continues to
pass OpenAPI 3.1 schema validation.

## Backward compatibility

Operations whose `param!` calls have no block in `0.12.0` emit
byte-identical output (SC-005). Operations whose `Hash`/`Array`
`param!` carries a declaring block gain the nested
`properties:` / `items:` schemas. The change is released as a
MINOR version bump (0.13.0) with a CHANGELOG entry.

## Out of scope

- The OpenAPI object-level `required:` array on nested objects
  (deferred per the spec's Assumptions section).
- Heterogeneous array `items:` (`oneOf: [...]`) — only the last
  item declaration in source order is used.
- Nested `param!` calls whose receiver is not the captured
  block variable (FR-006 explicitly rejects these).
- A block on a `param!` whose type is neither `Hash` nor `Array`
  (FR-008 — the block is silently ignored).
