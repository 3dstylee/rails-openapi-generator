# Feature Specification: respond_to Format Blocks

**Feature Branch**: `012-respond-to-format-blocks`

**Created**: 2026-05-20

**Status**: Draft

**Input**: User request: an action like

```ruby
def index
  authorize_access_index
  assign_rendering_parameters!(@project)

  respond_to do |format|
    format.html do
      gon.push(gon_params)
    end
    format.json
  end
end
```

is documented today with no entry for either format — the `respond_to`
block is opaque to the generator. The fix is to detect each `format.X`
call inside a `respond_to` block, treat each as a render at the
action's default view in that format, and document the operation with
the matching content types (e.g. status 200 with both
`application/json` and `text/html`). This complements feature 010 /
011 by closing the last common documentation gap.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Document an action with `format.html` and `format.json` (Priority: P1)

A developer's `index` action does `respond_to do |format|;
format.html { ... }; format.json; end`, and the controller's view
directory contains both `index.html.erb` and `index.json.jbuilder`.
When the document is generated, the operation's response under the
happy status (200 for GET) carries both `text/html` and
`application/json` content types — the JSON entry's schema is the
parsed jbuilder.

**Why this priority**: This is the entire motivation. Today the
operation is documented with no content (the `respond_to` block is
invisible to the generator); after the fix, both formats are
documented and a typed client knows exactly which response shapes are
on the wire.

**Independent Test**: Generate the document for an action that uses
`respond_to do |format|; format.html ...; format.json; end` and
confirm the operation's success response has both content types, with
the jbuilder schema attached to the JSON entry.

**Acceptance Scenarios**:

1. **Given** an action with `format.html { ... }` and `format.json`
   (no block) and both `index.html.erb` and `index.json.jbuilder`
   exist, **When** the document is generated, **Then** the operation's
   200 response has `content` with both `application/json` (jbuilder
   schema) and `text/html` keys.
2. **Given** the same action but only `index.json.jbuilder` exists
   (no `.html.erb`), **When** the document is generated, **Then** the
   operation's 200 response has only the `application/json` content
   type; the missing HTML view does not produce a `text/html` entry
   with an empty body.
3. **Given** the same action but only `index.html.erb` exists (no
   jbuilder), **When** the document is generated, **Then** the
   operation's 200 response has only the `text/html` content type.

---

### User Story 2 - Honor explicit renders inside format blocks (Priority: P2)

A developer's action does
`respond_to { |format| format.json { render json: { id: 1 } }; }` —
the JSON format gate has an explicit `render json:` block. When the
document is generated, that explicit render's schema is used for the
JSON content type, not the default view lookup.

**Why this priority**: The block-with-explicit-render pattern is
common in real codebases (often for `render json: serializer.as_json`
or `render json: { errors: ... }, status: :unprocessable_entity`).
Without it, the format-gate detection would miss the developer's
explicit intent.

**Acceptance Scenarios**:

1. **Given** `format.json { render json: { id: 1, ok: true } }`,
   **When** the document is generated, **Then** the operation's
   `application/json` schema documents `id` and `ok` (the literal
   render's schema), not the default `index.json.jbuilder`.
2. **Given** `format.json { render json: { errors: msgs }, status:
   :unprocessable_entity }`, **When** the document is generated,
   **Then** the operation has a 422 entry with the `application/json`
   content carrying the error schema, AND any other `format.X` in the
   same block contributes its own entry at the happy status.
3. **Given** `format.html { render "other_template" }`, **When** the
   document is generated, **Then** the `text/html` content for the
   200 entry is sourced from the explicitly rendered template's
   `.html.*` view (consistent with feature 011's template-render
   rules), not from the action's default `.html.*` view.

---

### Edge Cases

- **Bare `format.json` (no block)**: Falls back to the action's
  default view (`<controller>/<action>.json.jbuilder`). If that view
  does not exist, no JSON content type is emitted (no body-less
  `application/json` entry).
- **Bare `format.html` (no block)** or `format.html` with a block
  that contains no render call: same — falls back to the default
  view; if no `.html.*` view exists, no `text/html` content type is
  emitted.
- **`respond_to` with only one format**: An action that only does
  `respond_to { |format| format.json }` is documented as a JSON-only
  operation (the `text/html` content type is NOT emitted just because
  `respond_to` is involved).
- **Both formats at the same status, mixed view existence**: When
  `format.html` resolves to a real `.html.erb` and `format.json`
  resolves to a real `.json.jbuilder`, both content types appear under
  one status entry — the OpenAPI shape is `{200: {content:
  {application/json: ..., text/html: ...}}}`.
- **`format.X` for an unknown extension** (e.g. `format.xml`,
  `format.csv`): Out of scope for v1 — the generator currently has no
  mapping from `:xml` / `:csv` / `:pdf` to a content type. Such calls
  are silently ignored (the operation is documented as if only the
  known formats were present).
- **`respond_to` outside the action body**: A `respond_to` block in
  a helper method or `before_action` is detected the same way the
  action body's `respond_to` is detected — feature 010's walker
  already reaches helper / before_action bodies; the new detection
  inherits that surface.
- **Action with a `respond_to` AND a top-level `render json:`**:
  Both contribute; the top-level render contributes its JSON schema
  as today (feature 010), and the `respond_to`'s format gates
  contribute their content types at the action's default view. At
  the same status, the schemas union via the feature-010 rules
  (oneOf if distinct, dedup if identical).
- **`format.any` / `format.all` / `format.send(:json)`**: Out of
  scope for v1 — non-literal dispatch.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST detect `respond_to` blocks in
  statically-reachable code (action body, helper methods,
  `before_action` callbacks) and walk each block for `format.<symbol>`
  method calls.
- **FR-002**: For each `format.<symbol>` call where `<symbol>` is a
  known content-type identifier (initially `:json` and `:html`), the
  system MUST emit a content-type entry on the operation's response
  set:
  - `format.json` → `application/json`
  - `format.html` → `text/html`
- **FR-003**: When the `format.<symbol>` call has no block, or has a
  block that contains no render call, the system MUST resolve the
  content's body / schema via the action's default view
  (`<controller>/<action>.<ext>` where `<ext>` corresponds to the
  format) and emit:
  - For `:json` with a resolvable `.json.jbuilder` → the parsed
    jbuilder schema as the `application/json` schema.
  - For `:html` with a resolvable `.html.*` → an HTML-page content
    type (`text/html`) with no schema (today's HTML emission).
  - When no view resolves → NO content type is emitted for that
    format (the `format.X` call adds nothing to the operation).
- **FR-004**: When the `format.<symbol>` call has a block that
  contains a render call (`render json:`, `render "template"`,
  `render :symbol`, etc.), the system MUST use that explicit render
  as the source of the format's body / schema and status, per
  features 010 (json renders) and 011 (template renders).
- **FR-005**: A `format.<symbol>` call's status follows the same
  rule as today's renders: an explicit `status:` option (when
  present, e.g. inside the block's render) wins; otherwise the
  HTTP-method convention (GET/PUT/PATCH → 200, POST → 201, DELETE →
  204).
- **FR-006**: At a given status, when both `application/json` and
  `text/html` content types are contributed by separate `format.X`
  gates, the operation's response entry MUST emit both content types
  under one status key (OpenAPI 3.1 allows multiple content types per
  response):
  ```yaml
  '200':
    description: Successful response
    content:
      application/json:
        schema: { ... }
      text/html:
        schema: { type: string }
  ```
- **FR-007**: When the same format is contributed by both a
  `respond_to` gate and an existing site (e.g. a top-level
  `render json:` or a feature-011 template render), the schemas
  collapse per feature 010 FR-004 — identical schemas dedup; distinct
  schemas union into `oneOf` deterministically.
- **FR-008**: `format.<symbol>` calls for unknown content-type
  identifiers (e.g. `:xml`, `:csv`, `:pdf`) are silently ignored; the
  feature does NOT add support for these formats. A future feature
  may extend the mapping.
- **FR-009**: `format.any` / `format.all` / `format.send(name)` are
  silently ignored (non-literal dispatch).
- **FR-010**: An action that uses `respond_to` and contributes ANY
  resolvable format MUST NOT trigger the
  "response shape could not be determined" warning, since at least
  one content type is known. An action whose `respond_to` block
  contains only unknown / unresolvable formats is treated as if no
  format gates were present (the warning fires only when no
  statically-known content type contributes anywhere — feature 010
  FR-011 / feature 011 FR-008).
- **FR-011**: When `respond_to` is the operation's only signal and
  every gate resolves a view, the operation's kind is `:json` (so
  multi-content-type emission applies) unless every contributed gate
  is exclusively HTML — in which case the operation's kind is
  `:html_page` (single-entry, today's behavior). Mixed (HTML + JSON)
  → `:json` with both content types under the status entry.
- **FR-012**: Detection MUST rely only on static inspection — no
  controller action, helper, callback, or `respond_to` block is
  executed.
- **FR-013**: Generation MUST remain deterministic and continue to
  pass OpenAPI schema validation. Multiple content types under one
  response MUST be emitted in a stable order (`application/json`
  before `text/html`, ascending by content-type name).

### Key Entities *(include if feature involves data)*

- **Format Gate**: A `format.<symbol>` call inside a `respond_to`
  block, optionally with a body block carrying explicit renders.
  Sits alongside the JSON, head, and template-render sites the
  multi-status feature already produces.
- **Format-to-Content-Type Map**: The system's internal mapping of
  Rails format symbols to OpenAPI content-type strings (initially
  `:json` → `application/json`, `:html` → `text/html`). Unknown
  symbols have no mapping and are silently ignored.
- **Multi-Content-Type Entry**: An operation's `responses` entry at
  one status that carries more than one content-type schema (e.g.
  both `application/json` and `text/html`). OpenAPI 3.1 already
  supports this; the feature lifts it into the emission path.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An action whose body is
  `respond_to { |format| format.html { ... }; format.json; }` and
  whose controller has both `<action>.html.erb` and
  `<action>.json.jbuilder` views is documented with a 200 response
  carrying both `application/json` (jbuilder schema) and `text/html`
  content types.
- **SC-002**: When only one of the two views exists, only the
  matching content type appears in the documented response.
- **SC-003**: An action that combines `respond_to` with a top-level
  `render json:` at a different status emits a multi-entry response
  (`200` from the format gates, the other status from the explicit
  render) without losing either signal.
- **SC-004**: Operations that did not use `respond_to` in 0.10.0
  emit byte-identical output in this version — no regression on
  existing single-format endpoints.
- **SC-005**: 100% of generated documents continue to pass OpenAPI
  3.1 schema validation, including responses with multiple content
  types under one status; repeated runs on unchanged input produce
  identical output.

## Assumptions

- The Rails format symbols `:json` and `:html` are the only ones in
  scope for v1. They map to `application/json` and `text/html`
  respectively. Unknown format symbols (e.g. `:xml`, `:csv`,
  `:pdf`) are silently ignored, not mis-mapped.
- A `format.<symbol>` call with no block (or an empty block, or a
  block that does no render) is treated as "use the default view for
  this action in this format". This matches Rails runtime behavior.
- The default-view lookup for a `format.<symbol>` gate uses the
  same `ViewLocator` path as today, with a format hint corresponding
  to the gate's symbol — so the existing `format_hint: :json` /
  `format_hint: :html` machinery from feature 011 is reused.
- A `format.X` block whose body is a `render` call follows feature
  010 (for `render json:`) and feature 011 (for template renders) —
  the format gate is informational; the block's render rules
  determine status, schema, and content type.
- `respond_to` blocks reached through helper methods and through
  `before_action` callbacks are detected the same way as those in
  the action body (consistency with feature 010 R4 / feature 011).
- `respond_to` calls without a block argument (`respond_to do; end`)
  are syntactically rare and out of scope; only the
  `respond_to do |format| ... end` shape is detected.
- `format.any`, `format.all`, and dynamic dispatch (`send(:json)`)
  are out of scope (FR-009). They neither contribute content types
  nor cause the operation to be mis-classified.
- A future feature can extend the content-type map (XML, CSV, PDF)
  by adding entries to the symbol→content-type mapping; this v1
  does not.
- The OpenAPI 3.1 spec already supports multiple content types per
  response; this feature emits them in a deterministic order
  (`application/json` before `text/html` ascending by content-type
  name) for byte-stable output (FR-013).
