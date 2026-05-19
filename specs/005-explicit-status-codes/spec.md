# Feature Specification: Explicit Success Status Codes

**Feature Branch**: `005-explicit-status-codes`

**Created**: 2026-05-19

**Status**: Draft

**Input**: User request: detect an action's explicit success status code from
`head` calls and the `status:` option of `render` calls, and use it as the
documented response status instead of inferring the status from the HTTP method.
A `head` call documents a body-less response. When an action sets no explicit
status, keep the existing HTTP-method convention. Only happy-path (2xx/3xx)
statuses are considered.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Document the status code the action actually sets (Priority: P1)

A developer's actions set their success status explicitly — `head :ok`,
`render json: data, status: :created`, and so on. When the document is
generated, each operation's success response is filed under the status code the
action actually sets, not a status guessed from the HTTP method.

**Why this priority**: Today two actions that both do `head :ok` can be
documented with different status codes (e.g. `201` for a POST, `200` for a PUT)
purely because of the HTTP-method guess. That is inaccurate and inconsistent.
Reading the real status is the entire value of the feature.

**Independent Test**: Generate the document for actions that set explicit
statuses via `head` and `render status:` and confirm each operation's success
response uses that exact status code.

**Acceptance Scenarios**:

1. **Given** a `POST` action that does `head :ok`, **When** the document is
   generated, **Then** its success response is filed under `200` (not `201`).
2. **Given** a `PUT` action that does `head :ok`, **When** the document is
   generated, **Then** its success response is filed under `200` — the same as
   the `POST` action above.
3. **Given** an action that does `render json: data, status: :created`, **When**
   the document is generated, **Then** its success response is filed under
   `201`.
4. **Given** two actions that set the same explicit status by different means,
   **When** the document is generated, **Then** both are documented with that
   same status code.

---

### User Story 2 - A head response has no body (Priority: P2)

When an action responds with `head`, it returns no body. When the document is
generated, the success response for such an action is documented with its
status code and no response body schema.

**Why this priority**: A `head` response is inherently body-less; documenting a
body for it would be wrong. This refines Story 1's status detection with the
correct body treatment.

**Acceptance Scenarios**:

1. **Given** an action whose success path is a `head` call, **When** the
   document is generated, **Then** the success response has no body schema.
2. **Given** a `head :no_content` action, **When** the document is generated,
   **Then** its success response is filed under `204` with no body (unchanged
   from current behavior).

---

### User Story 3 - Fall back to the HTTP-method convention (Priority: P3)

When an action sets no explicit success status, the document continues to file
its success response under the conventional status for the HTTP method.

**Why this priority**: Most actions do not set an explicit status; the existing
convention must remain the default so the change is backward-compatible.

**Acceptance Scenarios**:

1. **Given** an action that sets no explicit status, **When** the document is
   generated, **Then** its success response uses the HTTP-method convention
   (`200` for read/update, `201` for creation, `204` for deletion).
2. **Given** an action that sets a status the system cannot map to a numeric
   code, **When** the document is generated, **Then** the HTTP-method
   convention is used and the run still completes.

---

### Edge Cases

- **Error status ignored**: An action with an error-status statement (e.g.
  `render status: :unprocessable_entity`) on a guard path — that status is
  ignored; only a happy-path (2xx/3xx) status is used.
- **Multiple happy statuses**: An action that sets more than one happy-path
  status — the last one (the main success path) is used.
- **Status as symbol or integer**: `head :created` and `head 201` resolve to the
  same code.
- **Unknown status symbol**: A status symbol the system does not recognize is
  treated as no explicit status — the HTTP-method convention applies.
- **Non-happy status only**: An action whose only explicit status is an error
  status falls back to the HTTP-method convention.
- **head vs. render status**: An action whose success path is a `head` is
  body-less; an action whose success path is a `render … status:` keeps the
  body that render produces.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST read an explicit success status from an action's
  `head` calls (`head :symbol` and `head <integer>`).
- **FR-002**: The system MUST read an explicit success status from the `status:`
  option of an action's `render` calls.
- **FR-003**: The system MUST map Rails HTTP status symbols (e.g. `:ok`,
  `:created`, `:accepted`, `:no_content`, `:see_other`) to their numeric codes.
- **FR-004**: The system MUST consider only happy-path statuses — 2xx and 3xx;
  statuses of 4xx/5xx (error statuses) MUST be ignored.
- **FR-005**: When an action sets more than one happy-path status, the system
  MUST use the last one.
- **FR-006**: When an action sets an explicit happy-path status, the system MUST
  file the operation's success response under that status code.
- **FR-007**: When an action sets no explicit (mappable, happy-path) status, the
  system MUST file the success response under the HTTP-method convention —
  `200` for GET/PUT/PATCH, `201` for POST, `204` for DELETE.
- **FR-008**: A success response produced by a `head` call MUST be documented
  with no response body schema.
- **FR-009**: Status detection MUST rely only on static inspection — no
  controller action is executed.
- **FR-010**: The feature MUST change only the documented status code (and, for
  `head`, the absence of a body); the response kind (JSON / HTML page / file
  download / undeterminable) and its other marks MUST be unaffected.
- **FR-011**: Generation MUST remain deterministic and continue to pass OpenAPI
  schema validation.

### Key Entities *(include if feature involves data)*

- **Status Signal**: An explicit status an action sets — a `head` call's
  argument, or the `status:` option of a `render` call.
- **Status Code**: A numeric HTTP status (e.g. `200`, `201`, `204`), resolved
  from a symbol or integer Status Signal.
- **Success Response**: The operation's documented happy-path response — a
  status code, an optional body schema, and a kind (unchanged by this feature
  except for the status code and the `head` body rule).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An action that sets an explicit happy-path status is documented
  with exactly that status code.
- **SC-002**: Two actions that set the same explicit status are documented with
  the same status code, regardless of their HTTP methods.
- **SC-003**: An action whose success path is a `head` call is documented with
  no response body schema.
- **SC-004**: An action that sets no explicit status is documented with the
  unchanged HTTP-method convention status.
- **SC-005**: 100% of generated documents continue to pass OpenAPI schema
  validation, and repeated runs on unchanged input produce identical output.
- **SC-006**: No operation's response kind or non-status marks change because of
  this feature — only status codes (and `head` body absence) change.

## Assumptions

- "Explicit status" means a status set by a `head` call or a `render … status:`
  option that is statically visible in the action body.
- Only 2xx and 3xx statuses are happy-path; 1xx statuses are not treated as a
  success status and fall back to the HTTP-method convention.
- When an action sets multiple happy-path statuses, the last one in source order
  is the main success path (consistent with how the happy-path `render json:` is
  already chosen).
- A status symbol the system does not have a mapping for is treated as "no
  explicit status" — the HTTP-method convention applies rather than guessing.
- A `head` response is always body-less; a `render … status:` response keeps
  whatever body that render already contributes.
- This feature builds on the existing generated document; it changes only the
  status code of operations that set an explicit status, plus the body absence
  for `head` responses.
