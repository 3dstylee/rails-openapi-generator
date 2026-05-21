# Feature Specification: rescue_from Handlers

**Feature Branch**: `014-rescue-from-handlers`

**Created**: 2026-05-20

**Status**: Draft

**Input**: User request: every controller inheriting from
`ApplicationController` (which declares a handful of `rescue_from`
handlers for `ActiveRecord::RecordNotFound`,
`Pundit::NotAuthorizedError`, `ActionController::ParameterMissing`,
etc.) silently emits `404` / `403` / `400` responses today. The
generator doesn't see these — so every operation's documented
response set is missing the stable error contract that's actually on
the wire. The fix is to detect `rescue_from` declarations on the
controller class chain and document each handler's renders as
response entries on every action in the controller, the same way
`before_action` handlers are documented today (feature 010 US3).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Document the standard `rescue_from` handlers from `ApplicationController` (Priority: P1)

A developer's `ApplicationController` declares three `rescue_from`
handlers — `record_not_found` → `404`, `forbidden` → `403`,
`bad_request` → `400` — each a private method doing a literal
`render json: { error: "..." }, status: :<symbol>`. When the
document is generated, every operation on every controller
inheriting from `ApplicationController` gains response entries
for `404`, `403`, and `400`, each with the handler's literal body
shape.

**Why this priority**: This is the entire motivation. Today the
`404`/`403`/`400` contract is invisible to API consumers reading
the generated doc — even though every endpoint emits these
responses at runtime. Surfacing them is a strict correctness gain.

**Independent Test**: Generate the document for an action on a
controller that inherits from a base class with `rescue_from
SomeError, with: :handler_method` (and the handler method renders
a literal body with an explicit status). Confirm the operation's
`responses` map contains the handler's status entry with the
handler's body schema.

**Acceptance Scenarios**:

1. **Given** `ApplicationController` declares
   `rescue_from ActiveRecord::RecordNotFound, with: :record_not_found`
   and the handler method does
   `render json: { error: "not_found" }, status: :not_found`,
   **When** the document is generated, **Then** every operation
   on every controller inheriting from `ApplicationController`
   has a `404` response entry with the literal `error` body
   schema.
2. **Given** the same setup with multiple `rescue_from`
   declarations (`:not_found`, `:forbidden`, `:bad_request`),
   **When** the document is generated, **Then** every operation
   gains all three response entries.
3. **Given** a controller with a per-controller `rescue_from`
   that overrides or supplements the base class's handlers,
   **When** the document is generated, **Then** the
   subclass's handler also contributes — both base-class and
   subclass handlers are documented (declarations stack via
   `rescue_handlers`, with the subclass's taking precedence at
   runtime; both shapes appear in the doc).

---

### User Story 2 - Document block-form `rescue_from` handlers (Priority: P2)

A developer's controller uses the block form —
`rescue_from FooError do |error| render json: { error: error.message }, status: :bad_request end`.
When the document is generated, the block's render contributes a
response entry the same way a method-form handler does.

**Why this priority**: Block-form handlers are less common but
widely used for terse one-line handlers. Without this story,
those handlers stay invisible.

**Acceptance Scenarios**:

1. **Given** `rescue_from ActiveRecord::RecordInvalid do |error|
   render json: { errors: error.record.errors }, status:
   :unprocessable_entity end`, **When** the document is
   generated, **Then** every operation on that controller has a
   `422` response entry with the block's literal body shape (a
   permissive object whose `errors` property captures the
   non-literal value).
2. **Given** a block-form handler whose body contains no render
   call (e.g. only logs and re-raises), **When** the document is
   generated, **Then** that handler contributes no response
   entry — but the generator does not raise.

---

### User Story 3 - Handlers in concerns inherited by the controller (Priority: P3)

A developer's `ApplicationController` includes a concern that
declares `rescue_from`. When the document is generated, those
declarations contribute exactly like declarations made directly
on `ApplicationController`.

**Why this priority**: Concerns are the Rails-idiomatic way to
package cross-cutting handlers. Without this story, a concern-
declared handler stays invisible — even though `rescue_handlers`
exposes it through the same API.

**Acceptance Scenarios**:

1. **Given** a concern `ErrorHandlers` that declares
   `rescue_from ActionController::ParameterMissing, with:
   :bad_request` and the concern is included into
   `ApplicationController`, **When** the document is generated,
   **Then** every action gets the `400` response entry.
2. **Given** a concern included into ONE specific controller
   (not the base class), **When** the document is generated,
   **Then** only operations on THAT controller and its
   subclasses get the handler's entries.

---

### Edge Cases

- **Handler method cannot be resolved** (the method is in a gem
  or not yet autoloaded, `MethodResolver.resolve` returns nil):
  silently skip the handler, do not raise; other handlers
  continue to contribute.
- **Handler method does not render** (it logs, raises, or
  silently returns): no entry is contributed by that handler.
  Other handlers contribute as expected.
- **Handler's render status is non-literal**
  (`render status: error.status_code`): the render's status
  resolves to UNRESOLVED → drops the contribution per existing
  rules (feature 010 R7).
- **Multiple `rescue_from` declarations resolving to the same
  status**: collapse per feature 010 FR-004 / FR-005 (identical
  schemas dedup; distinct schemas union into `oneOf`).
- **Re-raising handler**: if the handler raises a different
  exception (`raise OtherError`), we do NOT follow the
  re-raise chain. The handler's contribution is whatever it
  renders BEFORE the re-raise (which is typically nothing,
  since re-raise prevents the render).
- **`rescue_from StandardError, with: :catch_all`**: included
  in scope as a regular `rescue_from`. The catch-all's emitted
  shape is whatever the handler renders; we don't pessimize
  the documentation by adding the catch-all to every status.
- **Conflict with action body renders**: a `rescue_from`
  handler's `404` and an action body's
  `render json: { ... }, status: :not_found` at the same
  status union via the standard feature-010 rules. JSON-wins-
  over-HTML at the same status still applies (FR-006 of feature
  011).
- **Conflict with `before_action` renders**: same — both are
  treated as "additional render sites for this action"; the
  union happens at the operation level.
- **Anonymous controllers / controllers without a resolvable
  source file**: skipped silently. The handler may still be
  detected via the rescue_handlers chain, but the body walk
  needs a resolvable method source location.
- **Handler that uses `head` instead of `render json:`**:
  contributes a body-less entry at the head's status, same as
  any other `head` call site.
- **Controllers that override their parent's handler with a
  different status or body**: both shapes appear in the doc.
  This is conservative — it shows what the chain may emit
  collectively. (A future refinement could pick only the
  subclass's shape at a status.)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST read
  `controller_class.rescue_handlers` (an Array of
  `[exception_class_string, handler]` pairs) to discover every
  `rescue_from` declaration applicable to the controller class.
- **FR-002**: For each handler whose form is a Symbol method
  name, the system MUST resolve that method via the existing
  `MethodResolver`, walk its body for renders and `head` calls
  via the existing `RenderExtractor.collect_sites`, and add
  those sites to every operation's response set with `source:
  :rescue_from`.
- **FR-003**: For each handler whose form is a Proc / block,
  the system MUST walk the block body the same way a
  `before_action`-callback block is walked (feature 010 US3),
  collecting render and head sites from it.
- **FR-004**: A handler whose target method cannot be resolved
  (Method::SourceLocationUnavailable, missing file, gem code,
  any other failure) MUST be silently skipped. The generator
  MUST NOT raise because of any handler-resolution failure.
- **FR-005**: A handler's contribution applies to EVERY action
  in the controller — `rescue_from` does NOT support `only:` /
  `except:` filters, so no per-action filtering is needed.
- **FR-006**: Multiple `rescue_from` handlers contributing to
  the same status MUST collapse per feature 010 FR-004 / FR-005
  (identical schemas dedup; distinct schemas union into
  `oneOf`).
- **FR-007**: Handlers inherited from parent controllers and
  from concerns mixed into the controller MUST be included —
  `rescue_handlers` already returns the full chain.
- **FR-008**: The new sites MUST go through the existing
  schema-resolution path (`LiteralEvaluator`, including feature
  013's `ConstantResolver` for `in:` constraints, etc.); no new
  evaluation path is introduced.
- **FR-009**: Re-raising handlers (`raise OtherError` inside
  the handler) MUST NOT be followed; the handler's documented
  contribution is whatever it renders directly before any
  raise.
- **FR-010**: The "response shape could not be determined"
  warning MUST continue to fire only when no statically-known
  status entry contributes; `rescue_from`-derived sites now
  count as known statuses for this purpose.
- **FR-011**: Detection MUST rely only on static inspection
  (method body parsing) plus reading the `rescue_handlers`
  metadata — no controller action, callback, or handler is
  executed.
- **FR-012**: Generation MUST remain deterministic and continue
  to pass OpenAPI 3.1 schema validation.

### Key Entities *(include if feature involves data)*

- **Rescue Handler**: A `rescue_from` declaration on the
  controller class chain. Carries an exception-class name
  (informational only — not surfaced in OpenAPI), and a
  handler (either a Symbol method name or a Proc/block).
- **Handler Render Site**: A `render json:` / `head` /
  template-render call inside a rescue handler's body.
  Indistinguishable from a `before_action` site once collected
  — `source: :rescue_from` is the only diagnostic mark.
- **Rescue-Resolution Cache**: A per-generator-run map of
  `controller_class` → list of resolved handler sites. Mirrors
  `BeforeActionResolver`'s cache pattern. Prevents re-walking
  the same handler chain for every action in the controller.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For a controller inheriting from a base class
  with N `rescue_from` declarations whose handlers render
  literal bodies with explicit statuses, every action on
  that controller documents N additional response entries
  (one per unique status), each with the handler's body shape.
- **SC-002**: Handlers declared in a concern included into the
  base class contribute the same as handlers declared directly
  on the base class.
- **SC-003**: A handler whose method cannot be resolved is
  silently skipped; the generator continues and produces a
  valid OpenAPI 3.1 document.
- **SC-004**: Operations whose controllers have no
  `rescue_from` declarations on the entire class chain (empty
  `rescue_handlers`) emit byte-identical output to `0.13.0`.
- **SC-005**: 100% of generated documents continue to pass
  OpenAPI 3.1 schema validation; repeated runs on unchanged
  input produce identical output, including stable per-status
  collapse order.

## Assumptions

- The generator is being executed in a process that has the
  host Rails application loaded (the standard rake task / CLI
  entry points already trigger this). `rescue_handlers` is a
  public method on every `ActiveSupport::Rescuable` includer,
  which means every Rails controller exposes it; this includes
  `ActionController::Base` and `ActionController::API`.
- The handler's contribution is documented for EVERY action on
  the controller (and on every subclass that doesn't override
  the inherited handler). This matches Rails runtime semantics
  — `rescue_handlers` already merges inherited declarations.
- The handler-method's source file is parsed via the existing
  YARD / Ripper pipeline; this works for methods defined in
  the host application's code and in concerns the application
  includes. Methods defined in gems (e.g. Devise's helpers)
  are out of reach; those handlers are silently skipped.
- The same `LiteralEvaluator.resolver` set by feature 013 at
  pipeline startup applies to handler-body evaluation. A
  `rescue_from … with: :method_name` whose body uses
  `render json: { ... }, status: Constants::NOT_FOUND_STATUS`
  resolves the constant transparently — no extra wiring.
- A handler is resolved at most once per controller class per
  generator run; the result is cached. This mirrors
  `BeforeActionResolver`'s caching pattern.
- The catch-all `rescue_from StandardError, with: :foo` is
  treated like any other `rescue_from`. Its contribution is
  what its handler renders. We do NOT speculate that
  `StandardError` covers every status, and we do NOT add the
  catch-all's status to every other operation.
- The exception class name (`ActiveRecord::RecordNotFound`,
  etc.) is NOT surfaced in the OpenAPI document — only the
  handler's render's status and body shape. OpenAPI doesn't
  have a place for "this status is emitted when X exception
  is raised", and inventing one would be off-spec.
- This feature does NOT attempt to model exception flow:
  e.g. `find!` raising `RecordNotFound` doesn't itself add a
  404 entry — only the `rescue_from RecordNotFound, with:
  :foo` handler's render does. The exception's status
  inference is exactly the handler's render's status; we
  don't have a separate "exception → status" map.
