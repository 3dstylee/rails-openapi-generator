# Feature Specification: Implicit Empty Response

**Feature Branch**: `015-implicit-empty-response`

**Created**: 2026-05-20

**Status**: Draft

**Input**: User request: a controller action like
`update_role_request_sync_key` that does authorization, finds a
record, calls `update!`, and falls through with no `render` —
documents today as a `200` entry with no `content`, but also emits
the `"response shape could not be determined"` warning and marks
the response `undeterminable: true` internally. The user wants the
warning suppressed and the response treated as a "body-less success
at the HTTP-method convention status" — the same as how Rails itself
handles a no-render action at runtime (an implicit head, or 204 for
non-rendering actions). The OpenAPI document output for the
operation is already correct; only the warning channel needs to
quiet down.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - No-signal actions stop noising the warning channel (Priority: P1)

A developer's controller action does no `render`, no `head`, no
`redirect_to`, no `respond_to`, has no resolvable view template,
and inherits no `rescue_from` / `before_action` / helper that adds
a render. When the document is generated, the operation's success
response is documented as a body-less entry under the HTTP-method
convention status (200 / 201 / 204), AND the
`"response shape could not be determined"` warning is NOT emitted
for that route.

**Why this priority**: The warning is the entire motivation. The
documented output is already what the user wants; the warning is
pure noise on real-world Rails apps where many actions legitimately
fall through to Rails' implicit no-content response. Suppressing
it removes the false-positive signal.

**Independent Test**: Generate against a fixture action that does
authorization + `update!` and falls through (no render anywhere
reachable). Confirm the operation has one `200` entry with no
`content` AND `GenerationReport.warnings` contains no
`"response shape could not be determined"` line for that route.

**Acceptance Scenarios**:

1. **Given** a controller action that does only side-effect
   operations (`authorize`, `find`, `update!`) and no render call,
   **When** the document is generated, **Then** the operation has
   exactly one response entry (the HTTP-method convention status)
   with no `content` key.
2. **Given** the same action, **When** the document is generated,
   **Then** `GenerationReport.warnings` does NOT contain
   `"response shape could not be determined"` for that route.
3. **Given** the same action, **When** the document is generated,
   **Then** `Response#undeterminable?` is `false` (internal
   invariant — used to drive other warning paths in the future).

---

### User Story 2 - Actions with at least one signal preserve their existing behavior (Priority: P2)

When an action has ANY render, head, redirect, file download, view
template, or inherited render site (helper, before_action,
rescue_from), the existing behavior is preserved exactly. The
warning path for these cases — which today never fires unless the
classification is `:undeterminable` AND the action has no
signals — is unchanged.

**Why this priority**: Backward compatibility. The change must
NOT silence the warning for cases where it might still convey
information; the change is narrowly about the "no signal at all"
case.

**Acceptance Scenarios**:

1. **Given** an action that has `render json: foo` where `foo` is
   non-literal, **When** the document is generated, **Then** the
   operation's response is documented as today (a single entry
   under the convention status, body nil, kind `:json`, NO warning
   fires — the response is "JSON-shaped but body unknown", not
   "could not be determined").
2. **Given** an action that classifies as `:undeterminable` but
   has a `rescue_from` handler contributing a 404 entry, **When**
   the document is generated, **Then** the operation has both
   a convention-status entry and the 404, AND no warning fires
   (feature 014's behavior).
3. **Given** an action with `head :no_content`, **When** the
   document is generated, **Then** today's behavior is preserved:
   one 204 entry, no content, no warning.

---

### Edge Cases

- **`response_resilience_spec.rb` regression**: the existing test
  explicitly asserts the warning fires for an "undeterminable"
  fixture endpoint. That assertion must be inverted (or removed):
  the warning no longer fires for that endpoint. The fixture's
  documented output is unchanged.
- **Serializer-based responses (Blueprinter, AMS, etc.)**: these
  also fall through this path today and fire the warning. After
  this feature, they emit a body-less response without a warning.
  This is a documented limitation: the generator cannot statically
  see serializer output. A future feature could add explicit
  serializer detection.
- **GenerationReport summary**: the `warnings:` count in the run
  summary may go down significantly for real apps. This is the
  desired effect, not a regression.
- **Internal `Response#undeterminable?` predicate**: callers (today
  only the Generator's warning emit) will observe `false` where
  they previously got `true`. If a future feature wants to bring
  back the warning for a more specific case (e.g. "literal `render
  json:` with a non-literal value AND no view"), the predicate can
  be re-purposed; it's an internal API.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: An operation whose classifier returned
  `:undeterminable` AND has no reachable render sites (no
  `render_sites` on the action body, no helper / before_action /
  rescue_from extras) MUST be documented with one response entry
  under the HTTP-method convention status (GET/PUT/PATCH → 200,
  POST → 201, DELETE → 204), with no `content` key.
- **FR-002**: For that case, the `"response shape could not be
  determined"` warning MUST NOT be emitted into
  `GenerationReport.warnings`.
- **FR-003**: For that case, the `Response#undeterminable?`
  predicate MUST return `false` (instead of `true` as today).
- **FR-004**: Operations whose classifier returned anything OTHER
  than `:undeterminable` (`:json`, `:redirect`, `:file_download`,
  `:html_page`) MUST emit byte-identical output to `0.14.0`,
  including any existing warning behavior.
- **FR-005**: Operations whose classifier returned
  `:undeterminable` BUT have at least one reachable render site
  (e.g. a `rescue_from` handler, a helper render) MUST emit
  byte-identical output to `0.14.0`. The change applies ONLY to
  the "truly no signal" case.
- **FR-006**: Detection MUST rely on the existing
  `Classification.kind` and the existing `extra_sites` /
  `render_sites` collections — no new walker, no new data shape,
  no new configuration key.
- **FR-007**: The OpenAPI document MUST continue to pass schema
  validation. A body-less success response is valid OpenAPI 3.1.

### Key Entities *(include if feature involves data)*

- **No-Signal Action**: A controller action whose reachable code
  (action body + helpers + before_action + rescue_from) produces
  ZERO render sites and ZERO classification signals
  (`:json` / `:redirect` / `:file_download` / `:html_page`). The
  generator's behavior for these actions is the entire scope of
  this feature.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A controller action with no render call, no view,
  no redirect, no respond_to, no contributing extras is documented
  with one response entry at the convention status and no
  `content` key.
- **SC-002**: The
  `"response shape could not be determined"` warning is NOT
  emitted for the action in SC-001.
- **SC-003**: The OpenAPI document for the operation in SC-001
  is byte-identical to the pre-`0.15.0` output (same status,
  same description, same absence of `content`).
- **SC-004**: For any operation whose action has at least one
  render site OR classifies as `:json` / `:redirect` /
  `:file_download` / `:html_page`, the generated document is
  byte-identical to `0.14.0`. The warning behavior for these
  operations is unchanged.
- **SC-005**: 100% of generated documents continue to pass
  OpenAPI 3.1 schema validation; repeated runs produce identical
  output.

## Assumptions

- The OpenAPI document output for the targeted case is already
  what the user wants — the change is internal (the
  `undeterminable` flag) and warning-channel (the suppression).
  No structural change to the document.
- Serializer-based responses (Blueprinter, ActiveModelSerializer,
  etc.) fall through the same path because the generator cannot
  see their bodies statically. They previously fired the
  warning; they now don't. This is acceptable in practice because
  the warning fires far more often than it usefully diagnoses
  serializer cases — typical Rails APIs have many no-render
  actions whose Rails-default behavior is well-understood (an
  empty success). A future feature can add explicit serializer
  detection to restore the diagnostic where it's actionable.
- The HTTP-method convention status used today (GET/PUT/PATCH →
  200, POST → 201, DELETE → 204) is unchanged. This matches the
  user's request ("default empty 200 status" was the GET/PUT/PATCH
  case; POST and DELETE use 201/204 as today).
- The internal `Response#undeterminable?` predicate is preserved
  as an API surface — it now returns `false` for the targeted
  case, but the method remains for future use (e.g. if a more
  specific "we lost a signal we should have caught" warning is
  added later).
- The existing `spec/integration/response_resilience_spec.rb`
  test will be updated to assert the new behavior (the warning
  does NOT fire). This is a deliberate spec change, recorded in
  the CHANGELOG as part of the 0.15.0 release notes.
