# Feature 020: JSON Schema sidecar files

**Status**: ready to implement
**Created**: 2026-05-20
**Constitution**: V — bump `0.19.0` → `0.20.0`. Additive: templates and
actions without sidecars emit byte-identical schemas to `0.19.0`.

## Problem

The jbuilder parser produces a permissive `{}` schema for any property
whose value is a non-literal expression (`json.id user.id`,
`json.created_at obj.created_at`, etc.). The result is correct but
useless for downstream type generation — every model attribute is
typed as "anything".

Existing escape hatches (inline literal renders, jbuilder partials)
help for some cases but not for the common "json.<key> some.expression"
pattern that dominates real templates.

## Solution

A **JSON Schema sidecar file** sits next to a jbuilder template (or at
the action's conventional view path) and declares the OpenAPI body
schema directly. The sidecar's contents are used verbatim as the
response body / partial schema, replacing the parser's inference.
Standard JSON Schema syntax (Draft 2020-12, the dialect OpenAPI 3.1
uses) — editors give autocompletion, and the same file can be reused
at runtime for response validation (`json_schemer` / `json-schema`).

### Conventions

- **Partial sidecar**: `app/views/<dir>/_<name>.schema.json` next to
  `_<name>.json.jbuilder`. Used wherever a `partial: "<dir>/<name>"`
  call resolves to the partial.
- **Action-template sidecar**: `app/views/<controller>/<action>.schema.json`
  next to `<action>.json.jbuilder`. Used as the schema for the
  template-backed action's response.
- **Inline-render action sidecar**: same path —
  `app/views/<controller>/<action>.schema.json` — works even when no
  `<action>.json.jbuilder` exists. Overrides the inferred schema at
  the HTTP-method convention status.

The sidecar's contents are a single JSON Schema document. Recommend
declaring `"$schema": "https://json-schema.org/draft/2020-12/schema"`
for editor support, but the gem doesn't enforce or validate the
sidecar's dialect — it loads the JSON verbatim and uses it as the
OpenAPI schema.

## User Stories

### US1 (P1) — Partial sidecar

**Given** a partial `app/views/api/users/_user.json.jbuilder` and a
sidecar `app/views/api/users/_user.schema.json` declaring the User
shape, **when** another template references `partial: "api/users/user"`
(via `json.partial!` or `json.<key> @c, partial:`), **then** the
sidecar's schema replaces the parser's inference for that partial.

**Independent test**: fixture partial with a sidecar — the operation
documenting the consumer template carries the sidecar's typed
properties instead of permissive `{}`.

### US2 (P2) — Action sidecar overrides the action's response

**Given** an action whose schema would otherwise be inferred (from a
jbuilder template OR an inline `render json:`), **when** a sidecar
exists at `app/views/<controller>/<action>.schema.json`, **then** the
sidecar's schema replaces the inferred body for the convention-status
entry.

**Independent test**: fixture action with no view file and an inline
`render json: { ok: true }` plus a sidecar declaring richer shape —
the operation's 200 entry carries the sidecar's schema, not the
inferred `{ok: boolean}`.

### US3 (P3) — Cycle and resilience

**Given** a malformed sidecar (invalid JSON), a missing sidecar, or
a sidecar with a $ref pointing at a missing path, **when** the
generator runs, **then** the run must not raise. The gem warns about
the malformed file once and falls back to the parser's inference.

## Functional Requirements

- **FR-001**: When a jbuilder template path resolves, the gem MUST
  check for a `.schema.json` sibling (same dir, same basename with
  `.schema.json` replacing `.json.jbuilder`) and use its JSON
  contents verbatim as the schema if present.
- **FR-002**: When an action's classification produces a response,
  the gem MUST check for `<views_root>/<controller>/<action>.schema.json`
  and override the convention-status entry's body with the sidecar's
  schema if present. The override applies regardless of whether a
  jbuilder template exists or an inline `render json:` was used.
- **FR-003**: A sidecar that fails to parse (invalid JSON) MUST emit
  a `Report` warning naming the file and fall back to the parser's
  inferred schema. The generator MUST NOT raise.
- **FR-004**: The lookup is by file existence only. No registry or
  configuration map.
- **FR-005**: Sidecar schemas are cached per-path for a single run
  (loaded once even when referenced by many endpoints).
- **FR-006**: Operations and partials without sidecars MUST emit
  byte-identical output to `0.19.0`.
- **FR-007**: Sidecar override applies to JSON responses only. For
  `:html_page`, `:file_download`, `:redirect`, the sidecar is
  ignored.

## Out of scope

- Drift detection between sidecar and jbuilder (was originally US3
  in the recommendation; deferred to a future feature). A simple
  Rake task could compare the sidecar against the inferred schema
  and warn on missing fields. That's worth its own design pass.
- Sidecar variants per HTTP status — sidecar always documents the
  convention-status body. Documenting 422 / 4xx error shapes via
  sidecar is left for a future feature.
- YARD-tag-based schema annotations (`# @response_schema ...`) —
  the path-convention approach makes them unnecessary.
- `$ref` resolution between sidecars (the gem loads each sidecar as
  a standalone schema; users wanting reuse can copy/paste or rely on
  OpenAPI tooling's `$ref` resolution post-generation).

## Success Criteria

- **SC-001**: A partial with a sidecar contributes the sidecar's
  typed properties to every consumer (US1 motivating test).
- **SC-002**: An inline-render action with a sidecar documents the
  sidecar's schema, not the inferred literal-hash schema (US2 motivator).
- **SC-003**: Templates without sidecars emit byte-identical schemas
  to `0.19.0` (FR-006).
- **SC-004**: A malformed sidecar produces a warning but does NOT
  abort the run (FR-003).
- **SC-005**: Two consecutive runs produce byte-identical output for
  operations affected by sidecars (determinism).
