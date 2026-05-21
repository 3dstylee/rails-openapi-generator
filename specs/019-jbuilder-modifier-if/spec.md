# Feature 019: jbuilder modifier-if body extraction

**Status**: ready to implement
**Created**: 2026-05-20
**Constitution**: V (versioned backward-compatible output) — bump
`0.18.0` → `0.19.0`. Templates exercising modifier-`if` previously
produced an incomplete schema; the fix is additive.

## Problem

A jbuilder template using **modifier-`if`** for a `json.<key>` line:

```ruby
json.message @message
json.errors @errors if @errors.present?
```

loses the `errors` property. The shape of `:if_mod` (and `:unless_mod`)
in Ripper is `[:if_mod, condition, body]` — the **body is at index 2**.
`JbuilderParser#conditional_bodies` returns `[[node[1]]]` (the
**condition** node), so when `each_json_call` iterates the "branch
body" it sees `@errors.present?` (a method call, not a `json.*` call)
and skips. The `json.errors` line is never extracted.

Caught in the wild on
`app/views/api/v2/sales_vr/error.json.jbuilder` whose generated 403
schema reads `{type: object, properties: {message: {}}}` — `errors` is
silently dropped.

## User Story

### US1 (P1) — Modifier-`if` lines contribute their schema

**Given** a jbuilder template with a `json.<key>` line guarded by
modifier-`if` or modifier-`unless`, **when** the parser produces the
schema, **then** the guarded property must appear in the merged
schema (same posture as the `if` / `case` branches already merged
since feature 016).

**Independent test**: parse a template with `json.errors @errors if
condition` plus a regular line; the resulting schema's `properties`
includes BOTH keys.

## Functional Requirements

- **FR-001**: `JbuilderParser#conditional_bodies` MUST return the body
  (`node[2]`) — not the condition — for `:if_mod` and `:unless_mod`.
- **FR-002**: Existing `if` / `unless` / `elsif` / `else` / `case`
  / `when` parsing behavior is unchanged (regression coverage).
- **FR-003**: Templates with no modifier-`if`/`unless` emit
  byte-identical schemas to `0.18.0`.

## Out of scope

- Conditional-then-conditional ternaries (`json.x cond ? a : b`) — the
  body becomes a single expression; today's permissive `{}` posture
  still applies because the value cannot be statically typed.
- Modifier-`while` / `until` — these are loops, not conditionals
  contributing to the schema's union.

## Success Criteria

- **SC-001**: The motivating fixture parses to a schema with BOTH
  `message` and `errors` properties.
- **SC-002**: Operations whose jbuilder templates contain no
  modifier-`if`/`unless` emit byte-identical schemas to `0.18.0`.
- **SC-003**: Two consecutive runs produce byte-identical output for
  the affected operations.
