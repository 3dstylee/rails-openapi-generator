# Feature Specification: Implicit Params Detection

**Feature Branch**: `006-implicit-params`

**Created**: 2026-05-19

**Status**: Draft

**Input**: User request: detect request parameters an action uses implicitly via
the `params` object — `params[:key]`, `params.require(:key)`,
`params.permit(:a, :b)`, `params.fetch(:key)`, `params.dig(...)` — in the action
body and, recursively, in the receiverless helper methods it calls. Add each
discovered parameter with a permissive "any" schema. Skip parameters already
documented from `rails_param` `param!` declarations or as path parameters, and
skip Rails-internal keys (`controller`, `action`, `format`).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Document parameters read directly from `params` (Priority: P1)

A developer's action reads request input directly off the `params` object —
`params[:image]`, `params["token"]` — without a `rails_param` declaration. When
the document is generated, each such parameter appears in the operation, so the
endpoint's inputs are documented even when no `param!` is used.

**Why this priority**: Direct `params[:key]` access is by far the most common
way Rails actions read input. Without this, those parameters are invisible in
the document — the endpoint looks like it takes no input when it does.

**Independent Test**: Generate the document for an action that reads
`params[:image]` (and nothing via `param!`) and confirm `image` appears as a
parameter of that operation.

**Acceptance Scenarios**:

1. **Given** an action that reads `params[:image]`, **When** the document is
   generated, **Then** `image` appears as a parameter of that operation.
2. **Given** a parameter discovered only via `params[:key]`, **When** the
   document is generated, **Then** it is documented with a permissive ("any")
   schema.
3. **Given** an action reads `params[:id]` where `id` is already a path
   parameter, **When** the document is generated, **Then** `id` is documented
   once (not duplicated).
4. **Given** an action reads `params[:controller]`/`params[:action]`/
   `params[:format]`, **When** the document is generated, **Then** those
   Rails-internal keys are NOT documented as parameters.

---

### User Story 2 - Document parameters from strong-params calls (Priority: P2)

A developer's action declares input through strong parameters —
`params.require(:key)`, `params.permit(:a, :b)`, `params.fetch(:key)`,
`params.dig(:a, :b)`. When the document is generated, the keys named in those
calls appear as parameters of the operation.

**Why this priority**: Strong-params calls are the second most common input
pattern. They build on Story 1's `params` scanning but read keys from method
arguments rather than `[]` access.

**Acceptance Scenarios**:

1. **Given** an action calls `params.require(:project)`, **When** the document
   is generated, **Then** `project` appears as a parameter.
2. **Given** an action calls `params.permit(:name, :email)`, **When** the
   document is generated, **Then** `name` and `email` appear as parameters.
3. **Given** an action calls `params.fetch(:token)` or `params.dig(:a, :b)`,
   **When** the document is generated, **Then** the named keys appear as
   parameters.

---

### User Story 3 - Follow `params` use into helper methods (Priority: P3)

An action may read `params` indirectly — through a helper method it calls,
which itself may call another helper. When the document is generated, parameters
used inside those receiverless helper methods are discovered too, by following
the call chain.

**Why this priority**: Some actions delegate input handling to shared helpers.
This extends Stories 1 and 2 to reach `params` use that is not in the action
body itself.

**Acceptance Scenarios**:

1. **Given** an action calls a helper method that reads `params[:token]`,
   **When** the document is generated, **Then** `token` appears as a parameter
   of the action's operation.
2. **Given** a chain of helper methods reaching a `params` access, **When** the
   document is generated, **Then** the parameter is still discovered.
3. **Given** helper methods that call each other cyclically, **When** the
   document is generated, **Then** discovery does not loop and the run
   completes.

---

### Edge Cases

- **Dynamic key**: `params[variable]` — the key is not a literal and cannot be
  named statically; it is skipped.
- **Already declared**: a key present both as a `param!` declaration and a
  `params[:key]` access — the `param!` definition (with its type and
  constraints) wins; the implicit one is not added again.
- **Path parameter**: a key that is already a path parameter is documented once.
- **Rails-internal keys**: `controller`, `action`, `format` are never documented.
- **Nested access**: `params[:user][:name]` — the top-level key (`user`) is the
  documented parameter; deeper nesting is best-effort.
- **Unresolvable helper**: a helper whose definition cannot be located ends that
  branch of the scan without error.
- **No params use**: an action (and its helpers) that never touches `params`
  gains no parameters from this feature.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST detect parameter keys read via index access on the
  `params` object — `params[:key]` and `params["key"]`.
- **FR-002**: The system MUST detect parameter keys named in strong-params calls
  on the `params` object — `require`, `permit`, `fetch`, and `dig`.
- **FR-003**: The system MUST consider only literal keys (symbols or strings); a
  non-literal key (a variable or expression) is skipped.
- **FR-004**: The system MUST scan for `params` use both in the action body and,
  recursively, in the receiverless helper methods the action calls, following
  the call chain with a bounded depth and a cycle guard.
- **FR-005**: The system MUST document each discovered parameter with a
  permissive ("any") schema.
- **FR-006**: The system MUST NOT document a parameter already documented from a
  `rails_param` `param!` declaration or as a path parameter.
- **FR-007**: The system MUST NOT document the Rails-internal keys `controller`,
  `action`, and `format`.
- **FR-008**: Each discovered parameter MUST be documented once per operation,
  even when accessed multiple times or in multiple helpers.
- **FR-009**: Detection MUST rely only on static inspection — no controller
  action or helper method is executed.
- **FR-010**: The feature MUST be additive — path parameters, `param!`-derived
  parameters, response data, and all other operation content MUST be unchanged;
  only newly discovered implicit parameters are added.
- **FR-011**: Generation MUST remain deterministic and continue to pass OpenAPI
  schema validation; discovered parameters are emitted in a stable order.

### Key Entities *(include if feature involves data)*

- **Implicit Parameter**: A request parameter discovered from `params` usage
  rather than from a `param!` declaration — a name and a permissive schema.
- **Params Access**: A statically recognized use of the `params` object — an
  index access (`params[:key]`) or a strong-params call (`require`/`permit`/
  `fetch`/`dig`) — from which a parameter key is read.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An action that reads a parameter only via `params[:key]` has that
  parameter documented.
- **SC-002**: Keys named in `require`/`permit`/`fetch`/`dig` calls are
  documented as parameters.
- **SC-003**: A parameter used only inside a helper method the action calls is
  documented on the action's operation.
- **SC-004**: 0% of operations gain a duplicate parameter, a Rails-internal key,
  or a parameter that was already declared via `param!` or a path segment.
- **SC-005**: Generation of an application with cyclic helper methods completes
  without hanging or erroring.
- **SC-006**: 100% of generated documents continue to pass OpenAPI schema
  validation, and repeated runs on unchanged input produce identical output.

## Assumptions

- Implicit parameters are placed the same way `rails_param` parameters are: as
  query parameters for `GET`/`DELETE` operations and as request-body properties
  for `POST`/`PUT`/`PATCH` operations. (Static analysis cannot determine query
  vs. body; this mirrors the existing parameter placement.)
- Strong-params keys are flattened: `params.require(:user).permit(:name)`
  contributes `user`, `name` as separate parameters rather than a nested object.
  Modeling nested objects is out of scope for this feature.
- Implicit parameters are always optional and untyped ("any"); `params` access
  carries no type or required/optional information.
- Recursive helper scanning reuses the existing wrapper method-resolution
  mechanism (static, depth-bounded, cycle-guarded); a helper whose definition
  cannot be located ends that branch.
- This feature builds on the existing generated document; it only adds
  parameters that are not already present.
