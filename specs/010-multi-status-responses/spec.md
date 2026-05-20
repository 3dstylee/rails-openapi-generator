# Feature Specification: Multi-Status Responses

**Feature Branch**: `010-multi-status-responses`

**Created**: 2026-05-20

**Status**: Draft

**Input**: User request: document multiple JSON responses per operation — one
entry per HTTP status the action can produce — instead of only the single
happy-path response that is documented today. The motivating case is
`PATCH /api/v2/workflow/custom_maisokus/:id`, whose action does
`render json: publish_file_urls(...)` on success and
`render json: { error_messages: ... }, status: :unprocessable_entity` on
failure; today only the happy render is documented (and is even marked
"undeterminable" because the value is a method call), so the 422 error
contract is invisible to API consumers.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Document both the happy and error responses (Priority: P1)

A developer's action does one `render json:` on success and another
`render json: ..., status: :unprocessable_entity` on a validation failure.
When the document is generated, the operation has two response entries — one
under the happy status code, one under `422` — each with the schema of the
render that produced it (or no body when the render's argument is non-literal).

**Why this priority**: This is the entire motivation for the feature. Today
the error render is dropped on the floor; consumers cannot see what the API
returns on failure. Surfacing every render the action makes — under its own
status code — is the user-visible value of the feature.

**Independent Test**: Generate the document for an action that has one happy
`render json:` and one error `render json:, status: :unprocessable_entity`,
and confirm the operation's `responses` map has both status entries (e.g.
`200` and `422`), each filed under its own status with its own body.

**Acceptance Scenarios**:

1. **Given** a `PATCH` action with `render json: payload` on the happy path
   and `render json: { error_messages: msgs }, status: :unprocessable_entity`
   on a guard path, **When** the document is generated, **Then** the
   operation has two response entries (`200` and `422`), each with its own
   body section (literal payload → typed schema; non-literal argument → no
   body).
2. **Given** a `POST` action that does two `render json:` calls at the same
   happy status with the same shape, **When** the document is generated,
   **Then** the operation has one entry under that status with that one
   shape (no duplicate).
3. **Given** a `POST` action that does two `render json:` calls at the same
   status with **different** literal shapes, **When** the document is
   generated, **Then** the operation has one entry under that status whose
   body is the union of the two shapes (an OpenAPI `oneOf` of the unique
   shapes, in a deterministic order).
4. **Given** an action whose only render at a given status is a `head` (or a
   non-literal `render json:`), **When** the document is generated, **Then**
   the entry under that status has no body section.

---

### User Story 2 - Include renders reached through helper methods (Priority: P2)

A developer's action calls a helper method (defined either directly on the
controller, on a parent controller, or in a concern mixed into the
controller) that does a guard render — e.g. `render json: { error: "..." },
status: :forbidden`. The error response is documented just as if the
`render` call were directly in the action body.

**Why this priority**: Real Rails controllers routinely factor guard renders
into private helpers (`authorize_user!`, `require_login!`, etc.). If the
feature only scanned the action body, those status codes would still be
missing — that is the same problem this feature exists to solve, one level
deeper.

**Acceptance Scenarios**:

1. **Given** a private controller method `require_login!` that does
   `render json: { error: "unauthorized" }, status: :unauthorized` and an
   action that calls `require_login!`, **When** the document is generated,
   **Then** the operation has a `401` response entry with that body schema.
2. **Given** a guard helper defined in a `Concern` module mixed into the
   controller, **When** the document is generated, **Then** the helper's
   render shows up in the operation's response entries just like a helper
   defined directly on the controller class.
3. **Given** a helper method whose body cannot be located (no source file,
   not Ruby), **When** the document is generated, **Then** the action's own
   renders are still documented and the run completes successfully.

---

### User Story 3 - Include renders reached through `before_action` callbacks (Priority: P3)

A developer's controller has a `before_action :require_login!` (or the
callback is declared in a concern, or inherited from a parent). The
callback's renders (and `head` calls) contribute the same way a directly-
called helper does — under their own status code.

**Why this priority**: Guard renders in `before_action` callbacks are the
single most common source of "missing" error-status documentation. Without
this story, an API whose 401s are all handled by `before_action :authenticate`
would still have no documented 401s.

**Acceptance Scenarios**:

1. **Given** `before_action :authenticate` on the controller, and an
   `authenticate` method that does `render json: { error: "..." },
   status: :unauthorized`, **When** the document is generated, **Then** the
   action's operation has a `401` response entry with that body schema —
   without the action body mentioning `authenticate`.
2. **Given** `before_action :authenticate` declared in a concern included
   into the controller, **When** the document is generated, **Then** the
   401 entry is still produced (callback chain is followed across mixins
   and inheritance).
3. **Given** `before_action :authenticate, only: %i[update destroy]`,
   **When** the document is generated, **Then** the 401 entry appears on
   the operations whose action is in the `:only` list, and (best-effort)
   does NOT appear on operations excluded by `:only` / included by
   `:except`. *(If statically deciding the conditional is impractical, the
   spec falls back to documenting the 401 on every operation in the
   controller — see Assumptions.)*
4. **Given** a `before_action` whose target method cannot be resolved or
   whose controller class cannot be loaded, **When** the document is
   generated, **Then** the run completes; no `before_action`-derived
   entries are added for that action; no extra warning is emitted.

---

### Edge Cases

- **Same-status, identical bodies**: Two renders at the same status with the
  same shape collapse to one entry with that shape.
- **Same-status, different bodies**: Two literal `render json:` at the same
  status with different shapes collapse to one entry whose body is `oneOf`
  the two unique shapes, sorted by a stable key (so output is deterministic).
- **Head + render at same status**: One `head :ok` and one
  `render json: { id: 1 }, status: :ok` collapse into a single `200` entry
  with the render's body (a known body beats no body).
- **All renders non-literal at one status**: When every render at a given
  status has a non-literal argument, the entry under that status has a status
  code and no body. This is **not** "undeterminable" — the status is known,
  only the body shape is unknown.
- **No mappable status**: A render whose `status:` symbol is not in the
  Rails-status table is dropped from the response set (today's behavior for
  the happy-path-only path) — the spec MUST NOT emit a non-numeric or
  unknown status key.
- **No render at all**: An action with no `render`/`head`/redirect/file/view
  still gets the existing "response shape could not be determined" warning
  and a single fallback entry — this story's classifier changes do not
  reach that case.
- **Render in dead code**: A render statically present but unreachable (e.g.
  inside `if false`) is still documented — static inspection does not model
  flow analysis.
- **Multiple HTTP-method-convention renders**: When two renders carry no
  `status:` option, both fall under the same conventional status (e.g. `201`
  for POST) and collapse by the same union rule.
- **Higher-precedence kind present**: An action that is also classified as
  a redirect / file-download / HTML page is documented by that kind alone
  (current precedence is preserved); multi-status documentation applies
  only when the action is JSON-shaped.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST inspect every `render` and `head` call the
  action makes on every reachable path (not only the happy path) when
  building the operation's response set.
- **FR-002**: Each `render` and `head` call MUST contribute one entry keyed
  by its HTTP status: the status comes from the call's own `status:` option
  or `head` argument; when a `render json:` carries no `status:` option,
  it uses the HTTP-method convention (GET/PUT/PATCH → 200, POST → 201,
  DELETE → 204).
- **FR-003**: When multiple renders / heads share a status, the system MUST
  collapse them into one entry per (status, content-type) pair.
- **FR-004**: Within one status entry, the body MUST be the union of
  contributing render schemas:
  - 0 known bodies → no body section.
  - 1 known body → that body.
  - 2+ distinct known bodies → an OpenAPI `oneOf` of the unique bodies,
    serialized in a deterministic order.
- **FR-005**: A `head` call's contribution MUST be a body-less entry under
  its status. A `head` at the same status as a render with a known body
  MUST collapse into the render's body (not blank it out).
- **FR-006**: The system MUST inspect renders / heads reached through
  receiverless helper methods called from the action, recursively (reusing
  the existing controller-method walker). Methods defined in concerns
  mixed into the controller MUST be walked the same as methods defined
  directly on the controller.
- **FR-007**: The system MUST inspect renders / heads inside `before_action`
  callback methods declared on the controller (including those inherited
  from parents and from concerns) on a best-effort basis. If the controller
  class cannot be loaded, or a callback's target method cannot be resolved,
  that callback MUST be silently skipped — no extra warning is emitted, and
  the run MUST complete.
- **FR-008**: `before_action` filters with `only:` or `except:` MAY be
  honored when their option resolves to a literal array of action names
  (best-effort). Otherwise, the spec MAY fall back to documenting the
  callback's renders on every action in the controller — and MUST do so
  consistently across runs (FR-013).
- **FR-009**: Renders reached through `rescue_from` handlers, and renders
  implied by exception-raising calls (Pundit `authorize`, ActiveRecord
  `find`/`find_by!`, etc.) are **out of scope** for v1 and MUST NOT be
  inferred. A future feature MAY add them.
- **FR-010**: When the operation is classified as a redirect, a file
  download, or an HTML page, the existing single-response behavior MUST
  continue to apply; multi-status documentation activates only for
  JSON-shaped operations and for `head`-only operations.
- **FR-011**: The "response shape could not be determined" warning MUST
  continue to fire for an action that produces no statically known status
  entries (no render, no head, no redirect, no file download, no view).
  A status entry with no body (because every render at that status is
  non-literal) MUST NOT trigger the warning.
- **FR-012**: Detection MUST rely only on static inspection — no
  controller action or callback is executed.
- **FR-013**: Generation MUST remain deterministic and continue to pass
  OpenAPI schema validation.

### Key Entities *(include if feature involves data)*

- **Render Site**: A single `render json:` or `head` call (in the action
  body, in a helper method, or in a `before_action` callback) with its
  resolved status code and (for renders) its body schema (which may be
  unknown for a non-literal argument).
- **Response Entry**: One entry in the operation's `responses` map — keyed
  by a numeric HTTP status, carrying an optional body schema (or `oneOf` of
  schemas) for `application/json`.
- **Response Set**: The full collection of response entries for one
  operation. For a JSON-shaped operation, it may contain multiple entries
  (e.g. `200` and `422`); for a redirect / file-download / HTML-page
  operation, it remains a single entry as today.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An action that contains both a happy `render json:` and an
  error `render json: ..., status: <symbol>` is documented with both
  status entries.
- **SC-002**: A guard helper called from the action — directly on the
  controller, on a parent, or in a concern — contributes its renders to
  the operation's response set.
- **SC-003**: A `before_action` callback's renders are documented on
  operations whose action the callback applies to (best-effort `only:` /
  `except:` resolution per FR-008).
- **SC-004**: A status with multiple distinct literal body shapes is
  documented as one entry whose body is `oneOf` the unique shapes,
  byte-identically across repeated runs.
- **SC-005**: Operations that were single-response today and that contain
  no second render (no helper render, no `before_action` render) are
  documented byte-identically to before this feature.
- **SC-006**: 100% of generated documents continue to pass OpenAPI 3.1
  schema validation; repeated runs on unchanged input produce identical
  output.

## Assumptions

- "Reachable" means statically reachable through the walker that already
  follows receiverless helper calls from the action body, extended to also
  include the `before_action` callback chain on the controller class.
  Methods reached through dynamic dispatch (`send(name)`, `public_send(name)`)
  are out of scope unless `name` is a literal symbol.
- Concerns are Ruby modules included into the controller; the walker
  follows methods regardless of where they were defined (concern vs.
  parent vs. controller body).
- `before_action :symbol, only: [...]` / `except: [...]` are honored when
  the option is a literal array; non-literal conditions (`if:`, `unless:`,
  proc/lambda `only:`/`except:`) fall back to "applies to every action in
  this controller" — a strict superset of the real chain, which keeps the
  documentation truthful in the "may emit" sense even when it is not
  precise.
- `before_action :symbol, only: [...]` resolves the symbol against the
  controller class itself; private methods are walked the same as public
  ones.
- `rescue_from` handlers and exception-implied statuses are deferred to a
  future feature. Documenting them well requires modeling the
  exception → handler → status chain (Pundit, ActiveRecord, custom
  exceptions), which is a significant design surface on its own.
- The HTTP-method convention status (200/201/204) is used **only** for
  renders that set no explicit status. Once any render at any status is
  present, the response set is derived from the renders themselves; the
  convention does not silently add an extra entry.
- Same-status union ordering: schemas are sorted by their canonical JSON
  representation so the `oneOf` list is deterministic across runs.
- The single-response `Response` object remains in use for redirect /
  file-download / HTML-page operations and for the "no signals at all"
  fallback. Only the JSON / head-only path gains the multi-entry shape.
