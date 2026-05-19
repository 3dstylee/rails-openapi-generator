# Feature Specification: Wrapper Method Resolution for File Downloads

**Feature Branch**: `004-wrapper-method-resolution`

**Created**: 2026-05-19

**Status**: Draft

**Input**: User request: when a controller action calls a helper method instead
of `send_file`/`send_data` directly, follow that helper to its definition (in
the controller, an included module, or a parent controller) and detect a
`send_file`/`send_data` call inside it, so the action is still classified as a
file download. Resolution is static and recursive — a wrapper may call another
wrapper — bounded by a configurable maximum depth (default 5) and guarded
against cycles.

## Clarifications

### Session 2026-05-19

- Q: Which method calls in an action body does the resolver follow? → A: Only
  calls with no explicit receiver (the controller's own instance methods,
  including inherited and included ones). Calls made on an explicit receiver
  (`object.method`) are not followed — they cannot reach the controller's
  `send_file`/`send_data`.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Detect a download made through a wrapper method (Priority: P1)

A developer's controller actions stream files through a shared helper method
(e.g. `send_file_and_cleanup`) instead of calling `send_file` directly. When the
document is generated, such an action is still classified as a file-download
endpoint, because the generator follows the helper to its definition and finds
the `send_file` call inside it.

**Why this priority**: This is the core value. Today an action that downloads a
file via a helper is classified as undeterminable and documented as a bare
success response — wrong. Resolving one level of wrapper fixes the common case.

**Independent Test**: Generate the document for an application whose action
calls a helper method that itself calls `send_file`, and confirm the action is
marked as a file-download endpoint.

**Acceptance Scenarios**:

1. **Given** an action that calls a helper method which calls `send_file`,
   **When** the document is generated, **Then** the action is classified as a
   file-download endpoint.
2. **Given** the helper is defined in the same controller, an included
   module/concern, or a parent controller, **When** the document is generated,
   **Then** the helper is found and the action is classified correctly.
3. **Given** an action that calls a helper which does NOT lead to
   `send_file`/`send_data`, **When** the document is generated, **Then** the
   action is NOT classified as a file download.

---

### User Story 2 - Follow chains of wrapper methods (Priority: P2)

A helper method may itself delegate to another helper before reaching
`send_file`. When the document is generated, the generator follows the whole
chain method-by-method until it finds a download call or runs out of leads.

**Why this priority**: Real codebases layer helpers (a controller helper calling
a shared concern helper). Single-level resolution (Story 1) handles the common
case; recursive resolution handles the rest.

**Acceptance Scenarios**:

1. **Given** an action that calls helper A, which calls helper B, which calls
   `send_file`, **When** the document is generated, **Then** the action is
   classified as a file-download endpoint.
2. **Given** a chain that never reaches `send_file`/`send_data`, **When** the
   document is generated, **Then** the action is not classified as a download.

---

### User Story 3 - Keep resolution bounded and safe (Priority: P3)

Recursive resolution must not hang, loop, or fail on real-world code. When the
document is generated, resolution stops at a configurable maximum depth, never
revisits a method it has already seen, and quietly ends a branch when a method's
definition cannot be located.

**Why this priority**: Correctness and robustness of the recursion. It protects
Stories 1 and 2 from pathological inputs but delivers no new classification on
its own.

**Acceptance Scenarios**:

1. **Given** a chain of wrapper methods deeper than the configured maximum,
   **When** the document is generated, **Then** resolution stops at the limit
   and the run completes.
2. **Given** wrapper methods that call each other in a cycle, **When** the
   document is generated, **Then** resolution detects the cycle and does not
   loop.
3. **Given** an action that calls a method whose definition cannot be located,
   **When** the document is generated, **Then** that branch ends quietly — no
   error, and the action is not guessed to be a download.
4. **Given** the host configures a different maximum resolution depth, **When**
   the document is generated, **Then** resolution honors the configured value.

---

### Edge Cases

- **Method defined in an ancestor**: A helper inherited from a parent controller
  or an included concern is resolved by searching the controller's ancestry.
- **Same name in multiple places**: When more than one definition could match a
  call, the one the controller would actually use (nearest in its ancestry) is
  inspected.
- **Unresolvable call**: A call into a gem, a metaprogrammed method, or anything
  whose source cannot be located ends that branch without error.
- **Cycle**: Helper A calls B, B calls A — resolution tracks visited methods and
  stops rather than looping.
- **Depth limit reached**: A wrapper chain longer than the configured maximum is
  abandoned at the limit; the action stays undeterminable.
- **Direct call still works**: An action that calls `send_file`/`send_data`
  directly is detected without any resolution (unchanged behavior).
- **Explicit-receiver call**: A call such as `service.generate` runs on another
  object and cannot reach the controller's `send_file`; it is not followed.
- **Conditional / multiple helpers**: An action calls several helpers; each is
  followed, and the action is a download if any branch reaches `send_file`.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: When an action does not call `send_file`/`send_data` directly, the
  system MUST attempt to resolve the methods the action calls **with no explicit
  receiver** (the controller's own instance methods, including inherited and
  included ones) and inspect their bodies for a download call. Calls made on an
  explicit receiver (`object.method`) MUST NOT be followed.
- **FR-002**: Resolution MUST locate a called method's definition by searching
  the controller's own source, its included modules/concerns, and its ancestor
  controllers.
- **FR-003**: When more than one definition could satisfy a call, the system
  MUST inspect the definition the controller would actually invoke (the nearest
  in its method-resolution ancestry).
- **FR-004**: Resolution MUST be recursive — a resolved method that calls a
  further non-`send_file` method has that method resolved and inspected in turn.
- **FR-005**: Recursion depth MUST be bounded by a maximum that is configurable
  by the host application, defaulting to 5 levels; a chain exceeding the maximum
  ends without classifying the action as a download.
- **FR-006**: Resolution MUST guard against cycles by tracking already-visited
  methods (identified by class and method name) and MUST NOT inspect a method
  twice within one resolution.
- **FR-007**: A call whose definition cannot be located MUST end that branch of
  resolution without raising an error and without guessing.
- **FR-008**: An action MUST be classified as a file-download endpoint when any
  resolution branch reaches a `send_file`/`send_data` call.
- **FR-009**: Resolution MUST rely only on static inspection — no controller
  action or helper method is executed.
- **FR-010**: The feature MUST be additive — actions already classified (direct
  `send_file`/`send_data`, JSON, HTML page, etc.) are unaffected; only actions
  that were previously undeterminable can newly become file downloads.
- **FR-011**: Generation MUST remain deterministic and continue to pass OpenAPI
  schema validation.
- **FR-012**: A download detected through wrapper resolution MUST receive the
  same marks as a directly detected download (content type, note, tag, flag)
  and MUST be included in the run report's file-download count.

### Key Entities *(include if feature involves data)*

- **Wrapper Method**: A controller helper method that an action calls and that
  may, directly or transitively, perform a file download.
- **Method Definition**: The located source of a method — its body, available
  for inspection — found in the controller, a module, or an ancestor.
- **Resolution Path**: The chain of methods followed from an action to a
  download call (or to a dead end), bounded by the maximum depth.
- **Method Identity**: A method's class + name, used to detect cycles so no
  method is inspected twice in one resolution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An action that downloads a file through a single wrapper method is
  classified as a file-download endpoint.
- **SC-002**: An action that downloads a file through a chain of wrapper methods
  (up to the configured depth) is classified as a file-download endpoint.
- **SC-003**: Generation of an application containing cyclic wrapper methods
  completes without hanging or erroring.
- **SC-004**: An action calling a method whose definition cannot be located
  completes the run without error and is not classified as a download.
- **SC-005**: 0% of actions already classified as JSON, HTML page, or direct
  download change classification because of this feature.
- **SC-006**: Re-running generation on unchanged input produces an identical
  document.
- **SC-007**: A wrapper-detected download appears in the document with the same
  marks as a direct download and is counted in the run report.

## Assumptions

- This feature extends file-download detection only. Resolving `render` /
  `render json:` / `render html:` through wrapper methods is out of scope and
  may be addressed by a later feature.
- The maximum resolution depth defaults to 5 levels and is configurable by the
  host application; 5 is deep enough for realistic helper layering.
- Resolution searches the controller's static ancestry (its own source,
  `include`d modules/concerns, and parent controllers). Methods provided only by
  the framework or gems are treated as unresolvable.
- A method whose body is too dynamic to inspect statically (metaprogrammed,
  defined at runtime) is treated as unresolvable — its branch ends quietly.
- This feature builds on the existing generated document; it changes only
  actions that were previously undeterminable and now resolve to a download.
