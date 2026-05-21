# Feature Specification: jbuilder Partials & case/when Branches

**Feature Branch**: `016-jbuilder-partials-and-case-branches`

**Created**: 2026-05-20

**Status**: Draft

**Input**: User request: two jbuilder parser improvements that
together close real-world schema-loss cases in the generated
OpenAPI doc.

1. **Recursive partial resolution for `json.<key> collection, partial: "name"`** —
   today the parser handles `json.partial!` and `json.array!` partials,
   but it does NOT handle the equivalent shorthand
   `json.today_logs @today_logs, partial: "activity_log", as: :activity_log`.
   The `today_logs` key ends up as a permissive `{}` instead of
   `{type: array, items: <partial schema>}`. The user reported this
   on a real fixture with 4 sibling keys (`today_logs`, `week_logs`,
   `month_logs`, `old_logs`) all referencing the same partial.

2. **`case` / `when` branch merging** — today the parser merges
   branches of `if` / `unless` / `elsif` / `else` blocks, but
   `case` / `when` is silently skipped. Properties declared inside
   `when` bodies are lost from the schema. The user wants the same
   union semantics applied: all properties from all branches are
   collected into the same schema.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Document a collection property with a partial reference (Priority: P1)

A developer's jbuilder does
`json.today_logs @today_logs, partial: "activity_log", as: :activity_log`
where the partial is at
`app/views/api/v2/sales_vr/activity_logs/_activity_log.json.jbuilder`.
When the document is generated, the `today_logs` property is
documented as `{type: array, items: <partial's schema>}` — recovering
the partial's full shape, including any nested partial references
inside the partial (recursion).

**Why this priority**: This is the entire motivation. Four sibling
keys in the user's reported fixture all lose their shape today
(`today_logs`, `week_logs`, `month_logs`, `old_logs` all become
permissive `{}`). The schema gap is large and obviously fixable
because the partial's source is available.

**Independent Test**: Generate the document for a jbuilder that
uses the `json.<key> @collection, partial: "name", as: :name` form.
Confirm the `<key>` property has `type: array` and an `items`
schema that matches what the partial would emit standalone.

**Acceptance Scenarios**:

1. **Given** a jbuilder `json.today_logs @today_logs, partial:
   "activity_log", as: :activity_log` and an existing partial
   `_activity_log.json.jbuilder` that emits `json.id`, `json.message`,
   `json.created_at`, **When** the document is generated, **Then**
   `today_logs` is documented as
   `{type: array, items: {type: object, properties: {id, message, created_at}}}`.
2. **Given** a partial that itself references another partial,
   **When** the document is generated, **Then** the recursive
   resolution follows the chain — the outer items schema reflects
   the deepest resolved shape.
3. **Given** a `json.<key> @c, partial: "name"` call (no `as:`
   option), **When** the document is generated, **Then** the
   partial is still resolved and `<key>` is documented as
   `{type: array, items: <partial schema>}` — `as:` is informational
   for the runtime, not required for static resolution.

---

### User Story 2 - Merge case/when branches into one schema (Priority: P2)

A developer's jbuilder uses `case` to switch a key's shape on a
condition:

```ruby
case @user.role
when "admin"
  json.permissions @user.permissions
  json.audit_log @user.audit_log
when "manager"
  json.team_members @user.team_members
else
  json.role "member"
end
```

When the document is generated, all properties from all `when` /
`else` branches are present in the schema (union):
`{permissions, audit_log, team_members, role}`.

**Why this priority**: `case` is idiomatic Ruby for multi-branch
switches. Without merging, every `when` body is silently dropped
— a real schema loss. The `if`/`elsif`/`else` path already does
this; `case`/`when` should match.

**Acceptance Scenarios**:

1. **Given** a jbuilder with a `case` block that declares
   different keys in different `when` branches, **When** the
   document is generated, **Then** the schema's `properties`
   includes every key declared in every branch.
2. **Given** a `case` block whose `when` branches declare the
   same key with different types (e.g. `json.x 1` vs.
   `json.x "string"`), **When** the document is generated,
   **Then** the last branch's type wins (consistent with the
   existing if/else merge semantics).
3. **Given** a `case` block with an `else` branch, **When** the
   document is generated, **Then** the `else` body is walked the
   same as any `when` body.
4. **Given** a `case` block with no `else` (legal Ruby), **When**
   the document is generated, **Then** every `when` body is
   walked; the absent `else` contributes nothing.

---

### Edge Cases

- **Partial referenced by a non-literal name**
  (`json.X @c, partial: partial_name`): `partial_name` is
  unresolvable, the existing `partial_schema` short-circuits to
  nil, and the property degrades to today's permissive `{}`. No
  warning is added.
- **Partial whose file cannot be located**: same — silent
  degradation to `{}`. The existing `resolve_partial` returns nil
  when `views_root` is wrong or the file doesn't exist.
- **Partial that references itself (cycle)**: the existing
  `seen` list in `schema_for_file` prevents infinite recursion. A
  self-cycle resolves to a permissive `{}` at the cycle point.
- **`json.<key>` with a positional collection arg AND a block
  AND a `partial:` option**: rare in practice; the existing
  `add_property` block branch takes precedence (the block's
  contents are walked). The `partial:` option is ignored when a
  block is present — consistent with how Ruby's jbuilder
  actually behaves (the block wins).
- **`json.<key>` with `partial:` but no positional arg**: rare
  shape; documented as a single object (`<partial schema>`)
  rather than an array. Matches Rails' jbuilder semantics.
- **`case` with no `when` branches** (legal but pointless Ruby):
  walked the same way; produces no properties from the case
  block.
- **`case x; when 1, 2; ...; end`** (multi-condition `when`):
  treated as a single branch whose body is walked once. The
  conditions are irrelevant to schema extraction.
- **Nested `case` inside an `if` branch (or vice versa)**: the
  walker descends naturally — `each_json_call` recurses through
  conditional bodies, and `:case` becomes one of the recognised
  shapes alongside `:if` / `:unless` / `:elsif` / `:if_mod` /
  `:unless_mod`.
- **`case` with a non-literal subject** (e.g.
  `case current_user.role`): walked normally; the subject isn't
  evaluated. Every `when` body is unioned. Same posture as the
  existing `if` handling.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When a `json.<key>` call carries a literal
  `partial:` option in its argument hash, the system MUST
  resolve the partial via the existing `partial_name` /
  `resolve_partial` / `schema_for_file` chain. The resolution
  MUST be recursive — partials inside the partial are followed,
  cycle-guarded by the existing `seen` list.
- **FR-002**: When a `json.<key>` call with a `partial:` option
  ALSO has a positional argument (the collection), the resulting
  schema MUST be `{type: array, items: <partial schema>}`.
- **FR-003**: When a `json.<key>` call with a `partial:` option
  has NO positional argument, the resulting schema MUST be the
  partial's schema directly (a single-object form).
- **FR-004**: When a `json.<key>` call has a body block AND a
  `partial:` option, the block takes precedence (matching
  jbuilder's runtime behavior); the `partial:` option is
  ignored.
- **FR-005**: When a `json.<key>` call's `partial:` option is
  non-literal (an unresolvable expression), the existing
  fallback to permissive `{}` MUST be preserved. The generator
  MUST NOT raise.
- **FR-006**: When a `case <expr>; when ...; when ...; else;
  end` block is encountered during walking, EVERY `when` body
  AND the (optional) `else` body MUST be walked through
  `each_json_call`, contributing their properties to the same
  schema hash via the existing merge semantics (last-wins for
  duplicate keys).
- **FR-007**: A `case` block with no `else` MUST be walked
  completely; the missing `else` contributes nothing extra.
- **FR-008**: A `case` block with multi-condition `when`
  (`when 1, 2, 3`) MUST be treated as a single body — the
  conditions are ignored.
- **FR-009**: A `case` block whose subject expression is
  non-literal MUST be walked the same way as a literal
  subject — the subject's value is irrelevant to schema
  extraction.
- **FR-010**: Both improvements MUST live in
  `lib/rails_openapi_generator/jbuilder_parser.rb`. No other
  file MAY be modified (the schema-mapping, the cache, the
  walker shape are all unchanged).
- **FR-011**: Templates that do NOT use the
  `json.<key> @c, partial:` shape AND do NOT contain `case` /
  `when` blocks MUST emit byte-identical schemas to `0.15.0`.
- **FR-012**: Generation MUST remain deterministic and continue
  to pass OpenAPI 3.1 schema validation.

### Key Entities *(include if feature involves data)*

- **`partial:` option site**: A `json.<key>` call carrying a
  literal `partial: "name"` keyword in its argument hash —
  with or without a positional collection argument. The
  feature's first half resolves these.
- **`case` block**: A Ruby `case <expr>; when ...; when ...;
  else; end` AST node found while walking statements. The
  feature's second half adds it to the conditional-shape list.
- **Partial schema** (existing): The OpenAPI schema produced by
  `schema_for_file(partial_file, seen)` — already supports
  cycle-guarded recursion through nested partials.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A jbuilder with `json.<key> @collection, partial:
  "name", as: :name` produces a property with
  `{type: array, items: <fully-resolved partial schema>}`.
- **SC-002**: A partial that itself references another partial
  is followed recursively; the deepest partial's keys appear
  in the outer schema's `items.properties`.
- **SC-003**: A `case` block's `when` and `else` bodies all
  contribute their properties to the schema; properties from
  all branches are present in the union.
- **SC-004**: Templates without these shapes emit
  byte-identical schemas to `0.15.0` (no false positives, no
  schema drift).
- **SC-005**: 100% of generated documents continue to pass
  OpenAPI 3.1 schema validation; repeated runs on unchanged
  input produce identical output.

## Assumptions

- The `partial:` resolution reuses the existing
  `partial_name` / `resolve_partial` / `schema_for_file`
  chain — no new file-system access pattern, no new caching,
  no new cycle-detection mechanism.
- The `case` / `when` merge semantics match the existing
  `if` / `elsif` / `else` semantics (union of properties,
  last-wins for duplicate keys). The `case` subject is not
  evaluated — every branch is considered equally likely to
  run.
- Partials referenced by a non-literal name (an expression,
  a method call, a conditional) resolve to permissive `{}`,
  as today. We do not attempt to evaluate the name dynamically.
- A `json.<key>` call's `block` argument takes precedence over
  a `partial:` option when both are present, mirroring
  jbuilder's runtime behavior.
- The existing fixture in `spec/fixtures/dummy/app/views/api/...`
  is extended with one new partial (`_activity_log.json.jbuilder`)
  and one new template that exercises the
  `json.<key> @c, partial:` shape plus a `case`-merge case.
  No new controller fixture is needed if an existing controller's
  action can be repointed at the new view template — but a small
  new controller is also acceptable.
- This feature does NOT change the schema-mapping rules
  (`type: object`, `type: array`, property naming, literal-vs-
  permissive type recovery). Only the AST-walking changes.
