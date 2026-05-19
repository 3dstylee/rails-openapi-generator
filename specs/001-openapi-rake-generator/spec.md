# Feature Specification: OpenAPI Rake Generator

**Feature Branch**: `001-openapi-rake-generator`

**Created**: 2026-05-19

**Status**: Draft

**Input**: User description: "I want to create a Ruby gem for Rails app. Actually I have an app that is using rails_param for validating parameters. I want to use it for generating my OpenAPI for all the endpoints (check rails routes) via a rake task. The title and description of the endpoints should be extracted from the YARD comments above the method definition"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Generate an OpenAPI document for all endpoints (Priority: P1)

A developer working on a Rails application runs a single rake task. The tool
inspects every route the application exposes and produces one OpenAPI document
that lists each endpoint with its HTTP method and path.

**Why this priority**: This is the core value of the feature. Without a
generated document covering the application's routes, nothing else matters. It
delivers a usable artifact on its own.

**Independent Test**: Run the rake task against an application with several
defined routes and confirm an OpenAPI document is produced containing one entry
per route, each with the correct path and HTTP method.

**Acceptance Scenarios**:

1. **Given** a Rails application with multiple defined routes, **When** the
   developer runs the generation rake task, **Then** an OpenAPI document is
   written that contains an operation for every route.
2. **Given** the generation completes, **When** the developer validates the
   output, **Then** the document conforms to the OpenAPI specification format.
3. **Given** an application with no routes, **When** the rake task runs,
   **Then** a valid but empty OpenAPI document is produced and the developer is
   informed that no endpoints were found.

---

### User Story 2 - Populate request parameters from existing validations (Priority: P2)

A developer's application already declares parameter validations for its
controller actions. When the document is generated, each operation's request
parameters (names, types, required/optional status, and constraints) are
derived automatically from those existing validation declarations.

**Why this priority**: Parameter detail is what makes the generated document
genuinely useful to API consumers. It builds directly on Story 1 and reuses
information the developer has already written, avoiding duplicate effort.

**Independent Test**: Run the rake task against actions that declare parameter
validations and confirm each operation lists the same parameters with matching
types, required flags, and constraints.

**Acceptance Scenarios**:

1. **Given** a controller action that declares parameter validations, **When**
   the document is generated, **Then** the corresponding operation lists each
   declared parameter with its name and data type.
2. **Given** a parameter is declared as required, **When** the document is
   generated, **Then** the parameter is marked required in the operation.
3. **Given** a parameter declares constraints (e.g., allowed values, min/max,
   format), **When** the document is generated, **Then** those constraints
   appear on the parameter.
4. **Given** an action declares no parameter validations, **When** the document
   is generated, **Then** the operation is still included with an empty
   parameter list.

---

### User Story 3 - Extract endpoint titles and descriptions from documentation comments (Priority: P3)

A developer documents controller actions with structured documentation comments
placed directly above each action method. When the document is generated, the
summary and description of each operation are taken from those comments.

**Why this priority**: Human-readable summaries and descriptions improve the
usability of the generated document but are not required for it to be valid or
machine-usable. This refinement layers on top of Stories 1 and 2.

**Independent Test**: Run the rake task against actions that have documentation
comments and confirm the operation summary and description match the comment
content; run it against actions without comments and confirm operations are
still generated.

**Acceptance Scenarios**:

1. **Given** a controller action with a documentation comment above its method
   definition, **When** the document is generated, **Then** the operation's
   summary and description reflect that comment's content.
2. **Given** a controller action with no documentation comment, **When** the
   document is generated, **Then** the operation is still produced with an
   empty or omitted summary and description.
3. **Given** a documentation comment exists but the route it maps to is not
   exposed by the application, **When** the document is generated, **Then** the
   comment is ignored and no orphan operation is created.

---

### Edge Cases

- **Route without a backing action**: A route points to a controller or action
  that does not exist. The generator records a warning and skips the route
  rather than failing the whole run.
- **Route handled outside the application**: Routes mounted from external
  engines or redirects have no controller action to inspect; the generator
  includes the path/method with whatever information is available and notes the
  limitation.
- **Duplicate paths with different methods**: The same path served by multiple
  HTTP methods is represented as multiple operations under one path entry.
- **Dynamic path segments**: Route segments such as `:id` are represented as
  path parameters in the generated operation.
- **Conflicting information**: A parameter is described in a documentation
  comment but also declared in validations; the validation-derived definition
  takes precedence and the comment is used only for prose.
- **Malformed documentation comment**: A comment that cannot be parsed is
  ignored for that action; the operation is still generated and a warning is
  recorded.
- **Non-API routes**: Routes that serve assets or non-JSON HTML pages are
  included or excluded according to the configured route filter (see
  Assumptions).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST be distributed as a reusable package that a Rails
  application can add as a dependency.
- **FR-002**: The system MUST provide a rake task that triggers OpenAPI document
  generation.
- **FR-003**: The system MUST discover the application's endpoints by inspecting
  its defined routes.
- **FR-004**: The system MUST produce a single OpenAPI document containing one
  operation for each discovered endpoint, identified by HTTP method and path.
- **FR-005**: The generated document MUST conform to a supported version of the
  OpenAPI specification and pass OpenAPI schema validation.
- **FR-006**: The system MUST derive each operation's request parameters from
  the application's existing parameter validation declarations, including
  parameter name and data type.
- **FR-007**: The system MUST mark parameters as required or optional based on
  their validation declarations.
- **FR-008**: The system MUST translate parameter validation constraints (such
  as allowed values, numeric ranges, and formats) into the equivalent OpenAPI
  parameter constraints where a corresponding representation exists.
- **FR-009**: The system MUST represent dynamic route segments as path
  parameters on the corresponding operation.
- **FR-010**: The system MUST extract each operation's summary and description
  from structured documentation comments placed above the controller action
  method.
- **FR-011**: The system MUST generate operations for endpoints even when no
  parameter validations or documentation comments are present.
- **FR-012**: The system MUST write the generated document to a file at a
  configurable location.
- **FR-013**: The system MUST allow the set of routes considered for generation
  to be filtered/configured (e.g., to exclude non-API routes).
- **FR-014**: The system MUST report a summary of the run, including the number
  of endpoints processed and any endpoints skipped, with the reason for each
  skip.
- **FR-015**: The system MUST complete generation without modifying the host
  application's source code, routes, or runtime behavior.
- **FR-016**: The system MUST continue processing remaining endpoints when an
  individual endpoint cannot be fully analyzed, recording a warning rather than
  aborting the run.

### Key Entities *(include if feature involves data)*

- **Endpoint**: A single addressable operation of the application, identified by
  an HTTP method and a path. Carries optional summary, description, request
  parameters, and the controller action it maps to.
- **Route**: The application's declared mapping from an HTTP method and path
  pattern to a controller action. The source from which endpoints are
  discovered.
- **Parameter**: A named input to an endpoint, with a data type, a
  required/optional flag, and optional constraints. Derived from the
  application's parameter validation declarations.
- **Documentation Comment**: Structured prose authored above a controller action
  method, providing the human-readable summary and description for the
  corresponding endpoint.
- **OpenAPI Document**: The generated output artifact describing all endpoints
  in a standard, tool-readable format.
- **Generation Report**: A run summary listing endpoints processed, endpoints
  skipped, and warnings raised.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A developer can produce a complete OpenAPI document for their
  application by running a single command, with no manual editing required for
  it to be valid.
- **SC-002**: 100% of the application's discoverable endpoints appear in the
  generated document with the correct HTTP method and path.
- **SC-003**: 100% of generated documents pass OpenAPI schema validation.
- **SC-004**: For endpoints that declare parameter validations, every declared
  parameter appears in the generated document with a matching name, type, and
  required/optional status.
- **SC-005**: For endpoints that have documentation comments, the generated
  summary and description match the comment content.
- **SC-006**: When an individual endpoint cannot be analyzed, the run still
  completes and the generated document still includes every other endpoint.
- **SC-007**: The generation run reports the count of endpoints processed and
  skipped, so the developer can confirm coverage at a glance.
- **SC-008**: Re-running the generation task on an unchanged application
  produces an identical document.

## Assumptions

- The host application uses the `rails_param` library to declare controller
  parameter validations; parameter detail is derived from those declarations.
  Actions that validate parameters by other means yield operations with empty
  parameter lists.
- Documentation comments follow the YARD comment convention and are placed
  immediately above the controller action method definition.
- Endpoints are discovered from the standard Rails route set (equivalent to the
  `rails routes` output).
- The generated document targets OpenAPI 3.x; the exact minor version is an
  implementation decision to be settled during planning.
- The default output is a single document file written to a conventional
  location within the project, with the path overridable via configuration.
- Response bodies and status codes are out of scope for the initial version,
  because `rails_param` describes request inputs only; operations are generated
  with request information and a placeholder/default response. Response schema
  generation may be considered as a future enhancement.
- Authentication and security scheme documentation is out of scope for the
  initial version.
- The tool runs in a development or build environment where the host
  application can be loaded; it is not intended to run as part of serving
  production traffic.
