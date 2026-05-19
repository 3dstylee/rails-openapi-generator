# Feature Specification: Happy-Path Response Bodies

**Feature Branch**: `002-response-bodies`

**Created**: 2026-05-19

**Status**: Draft

**Input**: User description: "new feature: I want to include the response bodies (just the happy path for now). How should I proceed?"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Document the success response body of each endpoint (Priority: P1)

A developer generates the OpenAPI document for their application. For each
endpoint, the success ("happy path") response now carries a body schema
describing the shape of the data the endpoint returns, instead of only a bare
status code.

**Why this priority**: Response bodies are the half of the API contract that
the current document is missing. Without them, consumers know how to call an
endpoint but not what they get back. This is the entire value of the feature.

**Independent Test**: Generate the document for an application whose endpoints
return data, and confirm each success response contains a body schema that
matches the data those endpoints actually return.

**Acceptance Scenarios**:

1. **Given** an endpoint that returns a single resource, **When** the document
   is generated, **Then** its success response has a body schema describing that
   resource's fields.
2. **Given** an endpoint that returns a collection, **When** the document is
   generated, **Then** its success response body schema describes an array of
   resource objects.
3. **Given** the document is generated, **When** it is validated, **Then** it
   still conforms to the OpenAPI specification.

---

### User Story 2 - Stay valid when a response shape cannot be determined (Priority: P2)

A developer's application has endpoints whose response shape cannot be
determined by inspection. When the document is generated, those endpoints still
produce a valid success response (without a detailed body schema) and the run
reports which endpoints were affected.

**Why this priority**: Real applications have endpoints the tool cannot fully
analyze. The feature must degrade gracefully rather than fail or omit those
endpoints — consistent with the existing generator behavior.

**Independent Test**: Generate the document for an application that includes at
least one endpoint with an undeterminable response shape, and confirm the
endpoint still appears with a valid success response and is listed in the run
report.

**Acceptance Scenarios**:

1. **Given** an endpoint whose response shape cannot be determined, **When** the
   document is generated, **Then** the endpoint still has a valid success
   response and a warning is recorded.
2. **Given** such an endpoint, **When** the document is generated, **Then** the
   run still completes and every other endpoint is unaffected.

---

### User Story 3 - Use the conventional success status code (Priority: P3)

When the document is generated, each operation's success response is filed
under the status code conventional for that kind of request, so the document
reflects how the endpoint actually behaves.

**Why this priority**: A correct status code makes the response section
accurate and useful, but the body schema (Story 1) is the substantive content;
this refines presentation on top of it.

**Acceptance Scenarios**:

1. **Given** a resource-reading endpoint, **When** the document is generated,
   **Then** its success response is filed under a "200 OK" status.
2. **Given** a resource-creating endpoint, **When** the document is generated,
   **Then** its success response is filed under a "201 Created" status.
3. **Given** an endpoint that returns no content, **When** the document is
   generated, **Then** its success response is filed under a "204 No Content"
   status with no body schema.

---

### Edge Cases

- **Collection vs. member endpoint**: A collection endpoint's body is an array;
  a member endpoint's body is a single object. The two are distinguished and
  represented differently.
- **Nested resources**: A response field that is itself a structured object or
  an array of objects is represented as a nested schema.
- **Paginated responses**: A collection wrapped in a pagination envelope
  (e.g. data + metadata) is represented as the envelope shape, not a bare array.
- **No-content responses**: An endpoint that returns an empty body has a success
  response with no body schema.
- **Undeterminable response**: An endpoint whose response shape cannot be
  resolved produces a valid generic success response and a warning (Story 2).
- **jbuilder partials**: A template that renders a partial (`json.partial!`) is
  resolved by following the partial when it can be located; an unlocatable
  partial degrades to a permissive schema (FR-013).
- **Both sources present**: An action that both renders a view and contains an
  inline `render json:` literal — the inline literal `render json:` in the
  action body takes precedence, since it is the response that action actually
  returns.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST add a success ("happy path") response body schema
  to each generated operation that returns data.
- **FR-002**: The system MUST derive an operation's response body schema by
  static inspection of two sources: (a) the jbuilder view template the action
  renders, located by Rails view-path conventions (e.g.
  `app/views/<controller>/<action>.json.jbuilder`), and (b) inline
  `render json:` calls in the action body whose argument is a literal value.
  When neither source yields a shape, the response is treated as undeterminable
  (FR-007).
- **FR-013**: jbuilder constructs that cannot be resolved statically (e.g.
  dynamically computed keys, values produced by method calls, or partials that
  cannot be located) MUST be represented permissively — the field is included
  with an unconstrained type — rather than aborting the run.
- **FR-014**: An inline `render json:` whose argument is not a literal (a
  variable, a method call, a serializer instance) MUST NOT be guessed at; if no
  jbuilder template applies either, the operation falls back to the
  undeterminable-response behavior (FR-007).
- **FR-003**: The system MUST represent a collection endpoint's response body as
  an array of resource objects and a member endpoint's response body as a single
  resource object.
- **FR-004**: The system MUST represent nested objects and arrays within a
  response body as nested schemas.
- **FR-005**: The system MUST file each operation's success response under the
  conventional success status code (200 for reads/updates, 201 for creation,
  204 for no-content responses).
- **FR-006**: The system MUST omit the response body schema for operations that
  return no content.
- **FR-007**: When the response shape of an operation cannot be determined, the
  system MUST still produce a valid success response and record a warning naming
  the operation.
- **FR-008**: The system MUST NOT execute host controller actions or perform
  HTTP requests to determine response shapes; response detail MUST be obtained
  by static inspection only.
- **FR-009**: The generated document MUST continue to conform to the OpenAPI
  specification and pass schema validation with response bodies included.
- **FR-010**: Generation MUST remain deterministic — the same application
  produces an identical document on repeated runs.
- **FR-011**: The feature MUST cover only success/happy-path responses; error
  responses (4xx/5xx) are explicitly out of scope for this feature.
- **FR-012**: The system MUST continue to generate a complete document for
  endpoints that have request parameters and documentation comments but no
  determinable response — the new behavior is additive.

### Key Entities *(include if feature involves data)*

- **Response**: The description of what an endpoint returns on success — a
  status code plus an optional body schema.
- **Response Body Schema**: The structured description of the shape of the
  returned data: field names, types, and nested structures.
- **Resource Shape**: The set of fields (and their types) that make up a single
  returned resource object, the building block of both member and collection
  responses.
- **Response Source**: The artifact a resource shape is read from — either the
  action's jbuilder view template or a literal `render json:` argument in the
  action body (FR-002).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: For endpoints whose response shape is determinable, 100% have a
  success response with a body schema in the generated document.
- **SC-002**: 100% of generated documents pass OpenAPI schema validation with
  response bodies included.
- **SC-003**: For a collection endpoint, the documented response body is an
  array; for a member endpoint, it is a single object.
- **SC-004**: Every operation's success response appears under a status code
  appropriate to the request (read, create, or no-content).
- **SC-005**: When an endpoint's response shape cannot be determined, the run
  still completes, the document still validates, and the endpoint is named in
  the run report.
- **SC-006**: Re-running generation on an unchanged application produces an
  identical document.
- **SC-007**: A consumer reading the generated document can see, for a
  documented endpoint, both how to call it and the shape of a successful result
  — without reading the application's source.

## Assumptions

- "Happy path" means the single primary success response of an endpoint; error
  and alternate responses (4xx/5xx, redirects) are out of scope for this
  feature and may be addressed later.
- The conventional success status codes are: 200 for reads and updates, 201 for
  resource creation, 204 for endpoints that return no body.
- Response shapes are obtained by static inspection only; no controller action
  is executed and no HTTP request is made (consistent with the existing
  generator's no-execution guarantee).
- Response shapes come from jbuilder view templates and literal `render json:`
  arguments; applications that serialize responses by other means (serializer
  classes, non-literal renders) yield undeterminable responses for those
  endpoints (FR-007) and may be supported by a later feature.
- When an action both renders a view and has an inline literal `render json:`,
  the inline literal takes precedence (it is what the action actually returns).
- This feature builds on the existing generated document — routes, request
  parameters, summaries, descriptions, and tags are unchanged; response bodies
  are added alongside them.
- Field-level types in a response body schema are best-effort; when a field's
  type cannot be determined it is represented permissively rather than omitted.
