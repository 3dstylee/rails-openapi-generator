# Feature Specification: Redirect Response Status Code

**Feature Branch**: `009-redirect-status-code`

**Created**: 2026-05-20

**Status**: Draft

**Input**: User request: for endpoints whose action calls `redirect_to`, document
the correct redirect status code (and a body-less response) instead of falling
back to the HTTP-method convention (which currently mis-documents a redirecting
`POST` as `201 Successful response`). Today such actions also emit a
"response shape could not be determined" warning because they neither render
JSON nor resolve to a view — that warning must go away for redirects.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Document a redirect with its actual status code (Priority: P1)

A developer's `create` action does `redirect_to @parent_folder` after saving.
When the document is generated, the operation's success response is filed under
`302` (the Rails default for `redirect_to`) — not `201`, and not "successful
response with an undeterminable body".

**Why this priority**: Today every redirecting action is documented with the
HTTP-method-convention status (e.g. `201` for `POST`) and a missing-body
warning. That is wrong on two counts: the status is incorrect, and the body is
not "undeterminable" — there is intentionally no body. The whole point of the
feature is to make a redirecting endpoint document accurately.

**Independent Test**: Generate the document for a `POST` action whose only
response statement is `redirect_to some_path` and confirm the operation's
success response uses status `302`, has no body, and produces no
"response shape could not be determined" warning.

**Acceptance Scenarios**:

1. **Given** a `POST` action whose success path is `redirect_to @resource`,
   **When** the document is generated, **Then** its success response is filed
   under `302` with no body, and no "response shape could not be determined"
   warning is emitted for it.
2. **Given** a `GET` action whose success path is `redirect_to root_path`,
   **When** the document is generated, **Then** its success response is filed
   under `302` (not `200`) with no body.
3. **Given** an action that mixes a guard path returning early and a happy path
   that calls `redirect_to`, **When** the document is generated, **Then** the
   documented success response is the redirect (`302`, body-less).

---

### User Story 2 - Honor an explicit redirect status (Priority: P2)

A developer's action does `redirect_to path, status: :see_other` (or
`status: 301`, `status: :moved_permanently`, etc.). When the document is
generated, the success response is filed under the status the action actually
sets, not under `302`.

**Why this priority**: Rails lets `redirect_to` take any 3xx status; the
documented status must match what the action actually sets. This refines
Story 1 with explicit-status handling, but the default-302 case is the common
one.

**Acceptance Scenarios**:

1. **Given** an action that does `redirect_to path, status: :see_other`,
   **When** the document is generated, **Then** its success response is filed
   under `303`.
2. **Given** an action that does `redirect_to path, status: 301`, **When** the
   document is generated, **Then** its success response is filed under `301`.
3. **Given** an action that does `redirect_to path, status: :moved_permanently`,
   **When** the document is generated, **Then** its success response is filed
   under `301`.

---

### User Story 3 - Redirect classifies, doesn't fall through (Priority: P3)

An action whose only response statement is `redirect_to` no longer falls
through the classification pipeline to "undeterminable". It is classified as a
redirect and documented as such.

**Why this priority**: This is the visible symptom the user reported — the
warning log and the wrong `201`. Stories 1 and 2 already cover the correct
documentation; this story names the pipeline change explicitly so it doesn't
get lost.

**Acceptance Scenarios**:

1. **Given** an action whose only response statement is `redirect_to`, **When**
   the document is generated, **Then** the operation is **not** marked
   "response shape could not be determined" and **not** documented with an
   "undeterminable" body.
2. **Given** an action that does both `render json:` on a happy path and
   `redirect_to` on another happy path, **When** the document is generated,
   **Then** the existing `render json:` precedence still wins (a JSON response
   is documented, not a redirect). *(Establishes that this feature only
   activates when no JSON / file-download / inline-html / view-template signal
   applies.)*

---

### Edge Cases

- **Default 302**: `redirect_to path` with no `status:` option resolves to
  `302` (the Rails default), regardless of HTTP method.
- **Symbol vs. integer status**: `redirect_to path, status: :found`,
  `redirect_to path, status: 302`, and bare `redirect_to path` all resolve to
  the same code.
- **Unknown status symbol**: A `status:` symbol the system does not have a
  mapping for is treated as "no explicit status" — the default `302` applies.
- **Error status on redirect**: `redirect_to path, status: :unprocessable_entity`
  (an unusual but legal call) is ignored as a redirect signal; the action
  falls back to existing behavior. Only 3xx statuses are accepted as a
  redirect status.
- **Multiple redirects in one action**: When more than one `redirect_to` is
  reachable on a happy path, the last one in source order is the documented
  redirect (consistent with how the happy-path `render json:` is already
  chosen).
- **Redirect alongside render**: Precedence is unchanged — a happy-path
  `render json:` still wins over a `redirect_to` (the json render is the
  documented response).
- **Redirect alongside `head`**: A `head` call's explicit status still
  contributes to the operation's status (as today); a redirect's status only
  applies when the operation is classified as a redirect.
- **`redirect_back` / `redirect_back_or_to`**: Treated the same as
  `redirect_to` — a redirect response with the default `302` (or the explicit
  `status:` option, if given).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST detect a `redirect_to` (and `redirect_back`,
  `redirect_back_or_to`) call in an action's body via static inspection — no
  controller action is executed.
- **FR-002**: When an action's response is classified as a redirect, the
  operation's success response MUST be documented with status `302` by
  default.
- **FR-003**: When the `redirect_to` call specifies a `status:` option whose
  value resolves to a 3xx status code (by symbol or integer), the operation's
  success response MUST be documented with that status code instead of `302`.
- **FR-004**: A redirect response MUST be documented with no response body
  schema (a redirect has no body).
- **FR-005**: A redirect response MUST NOT trigger the
  "response shape could not be determined" warning, and MUST NOT be marked
  "undeterminable".
- **FR-006**: Redirect classification MUST sit below the existing happy-path
  signals in precedence — a happy-path `render json:`, a `send_file` /
  `send_data`, an inline `render html:`, or a resolvable view template still
  classifies the action as JSON / file-download / HTML-page (not as a
  redirect).
- **FR-007**: When an action has more than one happy-path redirect, the system
  MUST use the last one in source order.
- **FR-008**: An explicit `status:` whose symbol the system does not have a
  mapping for MUST be treated as "no explicit status" — the `302` default
  applies.
- **FR-009**: An explicit `status:` whose code is not 3xx MUST NOT be treated
  as a redirect status — the action falls back to existing classification.
- **FR-010**: This feature MUST change only how an action that would otherwise
  be "undeterminable" because of a `redirect_to` is documented. Operations
  classified as JSON / file-download / HTML-page / `head` MUST continue to be
  documented as they are today.
- **FR-011**: Generation MUST remain deterministic and continue to pass
  OpenAPI schema validation.

### Key Entities *(include if feature involves data)*

- **Redirect Signal**: A `redirect_to` (or `redirect_back` /
  `redirect_back_or_to`) call in an action body, optionally carrying a
  `status:` option.
- **Redirect Status Code**: The numeric 3xx HTTP status documented for the
  operation — `302` by default, or the code resolved from the `status:`
  option.
- **Redirect Response**: The operation's documented success response when the
  action is classified as a redirect — a 3xx status code, no body, and no
  "undeterminable" mark.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An action whose only response statement is `redirect_to` is
  documented with status `302` (or its explicit 3xx status) and no body —
  regardless of the route's HTTP method.
- **SC-002**: An action that previously produced the
  "response shape could not be determined" warning because of `redirect_to`
  no longer produces that warning.
- **SC-003**: Operations classified as JSON / file-download / HTML-page /
  `head` are documented with exactly the same status and body as before this
  feature (no regressions on non-redirect endpoints).
- **SC-004**: Repeated runs on unchanged input produce identical output, and
  generated documents continue to pass OpenAPI schema validation.

## Assumptions

- "Redirect" means a `redirect_to`, `redirect_back`, or `redirect_back_or_to`
  call statically visible in the action body. A redirect reached through a
  wrapper method or `before_action` is out of scope for this feature.
- The Rails default for `redirect_to` is `302 Found`; the system treats a
  redirect with no `status:` option as `302`.
- Only 3xx statuses count as a redirect status. A `status:` that resolves to
  a non-3xx code is ignored for the purpose of redirect classification (the
  action is then classified by the existing rules).
- When multiple happy-path redirects are reachable, the last one in source
  order is the documented redirect (consistent with the existing happy-path
  `render json:` rule).
- This feature only documents the redirect's status and the absence of a
  body. The redirect target (the `Location` header value) is dynamic at
  runtime and is **not** documented as a literal value; documenting a
  `Location` header schema is out of scope for v1.
- The existing happy-path precedence is unchanged: `render json:` >
  `send_file` / `send_data` > inline `render html:` > resolvable view >
  redirect > undeterminable.
