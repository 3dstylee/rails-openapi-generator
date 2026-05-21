# Feature Specification: Template Renders in Helpers

**Feature Branch**: `011-template-renders-in-helpers`

**Created**: 2026-05-20

**Status**: Draft

**Input**: User request: a controller action whose happy path is a
`render "path/to/template"` call inside a private helper method (with the
error path doing `render json: { ... }, status: :conflict`) is documented
today with only the error status (e.g. `409`) and not the happy template
status (e.g. `200`). The fix is to collect template renders the same way
the multi-status feature (010) already collects JSON renders and `head`
calls — across the action body, helper methods, and `before_action`
callbacks — and to honor an explicit `formats:` option when resolving
the template to a view file.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Document a happy template render that lives in a helper (Priority: P1)

A developer's controller action does an early-return error render and
then calls a private helper that does `render "namespace/controller/show",
formats: :json, handlers: [:jbuilder]`. When the document is generated,
the operation's response set contains the helper's template render
filed under the happy status (the HTTP-method convention, since the
template render carries no `status:` option), with the schema of the
resolved `.json.jbuilder` view — alongside the error status from the
action body's error render.

**Why this priority**: This is the entire motivation for the feature.
Today the helper's template render is dropped on the floor, so the
operation is documented with only the error status; the user-facing API
contract for the success path is invisible.

**Independent Test**: Generate the document for an action whose only
happy-path render is a `render "..."` template call inside a helper
method, and confirm the operation's `responses` map contains the
happy-path status (e.g. `200`) with the resolved jbuilder schema, plus
any other entries the existing rules already produce.

**Acceptance Scenarios**:

1. **Given** an action that calls a helper whose only render is
   `render "namespace/controller/show", formats: :json, handlers:
   [:jbuilder]`, and an action body that does
   `render json: { message: "..." }, status: :conflict` on a guard path,
   **When** the document is generated, **Then** the operation has two
   entries — the happy status (e.g. `200` for a PUT, with the jbuilder
   view's schema) and `409` (with the error render's body).
2. **Given** an action that calls a helper doing
   `render "namespace/controller/show"` (no `formats:` option), and a
   `.json.jbuilder` view exists for that template name, **When** the
   document is generated, **Then** the operation has a happy-status
   entry with the jbuilder schema (the JSON view is preferred today
   when both formats exist).
3. **Given** an action that calls a helper doing
   `render "namespace/controller/show", formats: :json` and only a
   `.html.erb` view exists (no `.json.jbuilder`), **When** the document
   is generated, **Then** the operation has a happy-status entry under
   the HTTP-method convention with no body (status known, body unknown
   because the requested JSON view does not exist).

---

### User Story 2 - Honor an explicit `formats: :html` to document the operation as HTML (Priority: P2)

A developer's helper does `render "pages/show", formats: :html`. The
operation is documented as an HTML page (the existing `:html_page`
kind), not as JSON — even when other helpers contribute JSON renders
at non-2xx statuses (those are still documented under their own
statuses).

**Why this priority**: Refinement of US1. Without it, an explicit
`formats: :html` is silently overridden by the today's "prefer JSON"
heuristic, which would mis-document an HTML endpoint as JSON.

**Acceptance Scenarios**:

1. **Given** an action whose helper does `render "pages/show",
   formats: :html` and an `.html.erb` view exists for that template,
   **When** the document is generated, **Then** the operation is
   documented with kind `:html_page` and the `text/html` content type
   (today's HTML-page behavior).
2. **Given** the same action with no other renders, **When** the
   document is generated, **Then** the operation is **not** documented
   as `:json`; the operation's success response is a single HTML-page
   entry.
3. **Given** an action whose helper does `render "pages/show",
   formats: :html` AND another helper does `render json: { error:
   "..." }, status: :unauthorized`, **When** the document is generated,
   **Then** the operation has both an HTML-page entry at the happy
   status and a `401` JSON entry (JSON precedence wins for the
   operation's kind classification — see Edge Cases / "kind precedence
   with mixed renders").

---

### User Story 3 - Template renders in `before_action` callbacks (Priority: P3)

A developer's `before_action` callback does a `render
"errors/forbidden", status: :forbidden`. The operation gains a `403`
entry with the resolved view's schema (jbuilder) or no body (other
formats), exactly the way the JSON renders in feature 010 do.

**Why this priority**: Consistency with feature 010 US3. Real callbacks
rarely template-render, but if they do, the documentation should not
silently miss them.

**Acceptance Scenarios**:

1. **Given** a `before_action :forbid_unless_admin` whose target does
   `render "errors/forbidden", status: :forbidden, formats: :json` and
   an `errors/forbidden.json.jbuilder` view exists, **When** the
   document is generated, **Then** the operation gains a `403` entry
   with that jbuilder schema.
2. **Given** the same callback but no `errors/forbidden.json.jbuilder`
   exists (only an `errors/forbidden.html.erb`), and the option says
   `formats: :json`, **When** the document is generated, **Then** the
   operation gains a `403` entry with no body (status known, JSON view
   unknown).
3. **Given** `only:` / `except:` filters on the callback, **When** the
   document is generated, **Then** the 403 entry appears on the
   actions the callback applies to (same rules as feature 010 US3).

---

### Edge Cases

- **No `formats:` option, both views exist**: The JSON view is
  preferred (today's `ViewLocator` behavior). The site contributes a
  JSON entry with the jbuilder schema.
- **No `formats:` option, only HTML view exists**: The HTML view is
  used; the site contributes an HTML-page entry.
- **No `formats:` option, no view exists**: The site contributes a
  status-known, body-less entry under the HTTP-method convention.
- **Explicit `formats: :json`, only HTML view exists**: The site
  contributes a status-known, body-less entry (the JSON view the
  render explicitly requested does not exist).
- **`formats:` is a literal array of symbols** (e.g.
  `formats: [:json, :html]`): The first explicitly listed format with
  a resolvable view wins. When neither resolves, the site is body-less
  under the HTTP-method convention.
- **`formats:` is non-literal** (a proc, a method call, an instance
  variable): The option is ignored; the today's "prefer JSON" lookup
  applies.
- **Bare action symbol render** (`render :edit`): Resolves the
  template name relative to the route's controller (today's behavior).
  The same `formats:` rule applies.
- **Mixed renders within one operation**: A template render's status
  is the HTTP-method convention (or its explicit `status:` option); a
  JSON render at the same status collapses with the template render's
  schema per feature 010's union rule (identical schemas dedup;
  distinct schemas union into `oneOf`).
- **HTML-template render alongside a JSON render at the same status**:
  JSON precedence wins for that status (the JSON render's body is
  documented). The HTML-template render is dropped at that status,
  not unioned with the JSON shape.
- **Kind precedence with mixed renders**: The operation's overall
  `kind` follows feature 010's precedence — `:json` > `:file_download`
  > `:html_page` > `:redirect` > `:undeterminable`. An action that has
  any JSON render (template or `render json:`) at any status
  classifies as `:json`. An action whose only renders are HTML-view
  template renders classifies as `:html_page`.
- **`render template: "name"`, `render action: :name`, `render
  partial:`**: Already handled today via `RenderResult.template`. This
  feature does not change those paths — it only adds the new
  helper / before_action coverage and the `formats:` honoring.
- **`render :ok`** (a bare status symbol): Today's behavior treats
  `:ok` as a template name (since it is a Symbol positional) — this
  edge case is out of scope; the existing behavior (look up a view
  named "ok", fail to find one) remains.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST collect template renders — `render
  "path"`, `render :symbol`, `render template: "path"`,
  `render action: :name` — from the action body, from helper methods
  reachable through the existing controller-method walker, and from
  `before_action` callbacks resolved by the existing
  `BeforeActionResolver`.
- **FR-002**: Each template render MUST contribute one response site
  (analogous to the JSON / head sites added by feature 010). The
  site's status is the render's `status:` option when present, or the
  HTTP-method convention when absent.
- **FR-003**: For each template render's site, the system MUST resolve
  the target template via the existing view-resolution rules,
  influenced by an explicit `formats:` option:
  - `formats: :json` (or a literal array containing `:json`) → look
    up `.json.jbuilder` for the template name. If found, the site
    contributes a JSON entry with the parsed jbuilder schema.
  - `formats: :html` (or a literal array containing `:html` without
    `:json`) → look up `.html.*` for the template name. If found,
    the site contributes an HTML-page entry.
  - No `formats:` option (or a non-literal value) → today's behavior:
    prefer `.json.jbuilder`, fall back to `.html.*`.
- **FR-004**: When the requested format's view does not exist, the
  site MUST contribute a body-less entry under its resolved status —
  not be silently dropped. The status is known; the body is unknown.
- **FR-005**: Template-render sites participate in the same per-status
  union / dedup rules as JSON sites (feature 010 FR-004 / FR-005). A
  template render resolving to `.json.jbuilder` and a `render json:`
  at the same status union into a single entry whose body is the
  unique-schema set (one schema or `oneOf`).
- **FR-006**: An HTML-template render and a JSON render at the same
  status MUST collapse into one entry whose body is the JSON render's
  body (JSON wins). The HTML template's body at that status is
  dropped; this matches feature 010's "JSON precedence over HTML" rule.
- **FR-007**: The operation's overall `kind` is `:json` whenever any
  JSON render — `render json:` or a template render resolving to a
  jbuilder view — contributes any entry; otherwise the existing
  classification precedence (`:file_download` > `:html_page` >
  `:redirect` > `:undeterminable`) applies.
- **FR-008**: The "response shape could not be determined" warning
  MUST continue to fire only when no statically known status entry
  contributes (the feature-010 rule), now including the new
  template-render sites in "known".
- **FR-009**: `format.json { render ... }` blocks inside `respond_to`
  and renders selected through dynamic dispatch (`send(name)`,
  `public_send(name)`) are out of scope and MUST NOT be inferred.
- **FR-010**: Detection MUST rely only on static inspection — no
  controller action, helper, or callback is executed.
- **FR-011**: Generation MUST remain deterministic and continue to
  pass OpenAPI schema validation.

### Key Entities *(include if feature involves data)*

- **Template Render Site**: A `render "path"` / `render :symbol` /
  `render template:` / `render action:` call located somewhere in the
  reachable code, with its `status:` and `formats:` options resolved.
  Sits alongside the JSON and head sites the multi-status feature
  already produces.
- **Format Hint**: The literal value of a render's `formats:` option,
  if present and literal — a Symbol or an Array of Symbols. Non-
  literal values are absent.
- **Resolved View**: The `ViewLocator` match for a template name
  guided by the format hint. May be a JSON view, an HTML view, or
  nothing (no view exists for the requested combination).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An action whose happy path is a template render inside
  a helper method is documented with the happy status entry; the
  documented body is the resolved jbuilder schema when a
  `.json.jbuilder` exists for the template.
- **SC-002**: An action whose template render carries
  `formats: :html` is documented as `:html_page` when no JSON render
  contributes; otherwise it remains `:json` (per FR-007).
- **SC-003**: A template render whose view cannot be resolved
  contributes a status-known, body-less entry — not nothing. The
  operation's other entries (from JSON renders or `head`) are
  unaffected.
- **SC-004**: Operations whose existing single-template-render
  behavior worked correctly today (e.g. the existing dummy fixture's
  HTML-page and jbuilder-view endpoints) MUST emit byte-identical
  output to `0.9.0`.
- **SC-005**: 100% of generated documents continue to pass OpenAPI
  3.1 schema validation; repeated runs on unchanged input produce
  identical output.

## Assumptions

- "Helper methods" means the same set the existing controller-method
  walker traverses — receiverless calls from the action body,
  bounded by `Configuration#method_resolution_depth`.
- "Reachable" template renders include those in concern methods
  mixed into the controller (the walker resolves them by name the
  same as direct methods).
- `before_action` callback template renders use the existing
  `BeforeActionResolver` to filter by `only:` / `except:` (feature
  010 US3); a callback with `only: [:destroy]` contributes its
  template entry only to the `destroy` action.
- `formats:` honors a literal Symbol or a literal Array of Symbols.
  When the option is a Proc, a method call, an instance variable, or
  any non-literal value, the option is ignored and today's
  "prefer JSON" lookup applies.
- `handlers:` (`render "...", handlers: [:jbuilder]`) is informational
  — the lookup is by file extension, not by handler name. The
  feature does not honor `handlers:` separately; whatever view file
  matches the requested format wins.
- The existing `RenderResult.template` field is preserved for backward
  compatibility but is no longer the sole template-resolution path —
  the new mechanism collects every template render as a site.
- `render template: "..."` and `render action: :name` are already
  detected today (via `RenderResult.template`); this feature
  generalizes that detection to every reachable body and to the
  multi-site model.
- This feature changes only how template renders contribute to the
  operation's response set. Operations classified as `:redirect`,
  `:file_download`, or whose only render is the same as before this
  feature, MUST be documented byte-identically to `0.9.0` (SC-004).
