# Feature 021: Auto-extract `example` from literal values

**Status**: ready to implement
**Created**: 2026-05-20
**Constitution**: V — bump `0.20.0` → `0.21.0`. The generated documents
gain an `example` key per primitive-typed schema; OpenAPI 3.1 consumers
treat this as an additive enrichment, but the output is **not**
byte-identical to `0.20.0` for templates with literal values. The
schema's `type` and field structure are unchanged.

## Problem

The parser sees a literal in a jbuilder template (`json.role "member"`)
and extracts the type (`{type: string}`) but discards the actual value.
The literal value would be a perfectly good `example` for documentation
viewers (Swagger UI, Redoc, Scalar) and SDK generators — but today the
user has to redeclare it in a sidecar to surface it in the docs.

## Solution

`LiteralEvaluator.schema_for` already receives the literal Ruby value
(String / Integer / Float / Boolean) before deciding on the type. Emit
the value alongside the type as the OpenAPI `example`:

```ruby
json.role "member"   # → { "type": "string",  "example": "member" }
json.id 42           # → { "type": "integer", "example": 42 }
json.price 9.99      # → { "type": "number",  "example": 9.99 }
json.active true     # → { "type": "boolean", "example": true }
```

For composite types, recursion handles property-level examples naturally:

```ruby
json.user do                # → { "type": "object",
  json.id 42                #     "properties": { "id": { "type": "integer", "example": 42 },
  json.name "Alice"         #                     "name": { "type": "string", "example": "Alice" } } }
end
```

A literal array contributes both an items schema (with example from
the first element) and an array-level example showing the whole list:

```ruby
json.tags ["a", "b"]
# → { "type": "array",
#     "items": { "type": "string", "example": "a" },
#     "example": ["a", "b"] }
```

Non-literal expressions (`json.id user.id`) stay permissive (`{}`) — no
example, no change from `0.20.0`.

## User Stories

### US1 (P1) — Primitive literals carry an example

**Given** a `json.<key> <literal>` line where the literal is a String,
Integer, Float, or Boolean, **when** the parser builds the schema,
**then** the property's schema must include `"example": <literal>`
alongside `"type"`.

**Independent test**: parse a template with each primitive literal
type; assert each property's schema has the expected `example` value.

### US2 (P2) — Composite literals propagate examples

**Given** an inline `render json: { id: 42, role: "admin", tags: ["x"] }`,
**when** the parser builds the response body, **then** the resulting
schema must carry property-level `example`s on every literal leaf.

### US3 (P3) — Sidecars override generated examples

**Given** a sidecar declaring its own `example` on a property, **when**
the schema is used, **then** the sidecar's `example` wins (the sidecar
is loaded verbatim, replacing the inferred schema entirely per
feature 020).

## Functional Requirements

- **FR-001**: `LiteralEvaluator.schema_for(value)` MUST add an
  `"example"` key whose value is the input value, for primitive types
  (String, Integer, Float, true, false).
- **FR-002**: For Array values, the items schema receives an example
  via recursion on the first element, AND the array schema receives
  an `"example"` key whose value is the full array (when non-empty).
- **FR-003**: For Hash values, recursion handles per-property examples;
  the object-level schema receives NO top-level `"example"` (would be
  redundant with property-level examples).
- **FR-004**: Non-literal expressions continue to evaluate to the
  permissive `{}` schema with no example (today's behavior preserved).
- **FR-005**: Sidecar JSON Schema files are loaded verbatim and
  override any inferred example — this is already the case (feature
  020) and continues to hold.

## Out of scope

- Multi-example collections (OpenAPI's `examples` keyword as a sibling
  of `content`). Users wanting multiple named examples can author them
  in a sidecar.
- Per-action example annotation via YARD tags.
- Example coverage of `extract!` arguments — these don't have a
  static value (the right-hand side is `obj.attr`, not a literal).
- Example coverage for non-jbuilder paths (inline `render json:` IS
  covered because it flows through `LiteralEvaluator.schema_for`
  upstream; this isn't a separate path).
- A configuration flag to disable example emission. Always-on for v1;
  add a flag later if requested.

## Success Criteria

- **SC-001**: Every primitive-typed property emitted from a literal
  value carries an `example` matching the source literal.
- **SC-002**: Composite literal renders (`render json: { ... }` and
  nested `json.x do ... end` blocks) propagate examples to every
  leaf property.
- **SC-003**: Templates with no literal values emit byte-identical
  schemas to `0.20.0` (the new code path fires only when a literal
  is present).
- **SC-004**: The output document remains valid OpenAPI 3.1.
- **SC-005**: Two consecutive runs produce identical output for
  affected operations (determinism).
