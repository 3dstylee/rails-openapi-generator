# Feature Specification: HTML Page & File Download Endpoints

**Feature Branch**: `003-html-page-endpoints`

**Created**: 2026-05-19

**Status**: Draft

**Input**: User request: detect controller actions that render an HTML page or
send a file download rather than a JSON response, and mark each such endpoint
in the generated document four ways — a non-JSON response content type, a note
in the operation description, a dedicated tag for grouping, and a
machine-readable flag.

## Clarifications

### Session 2026-05-19

- Q: Should `send_file`/`send_data` file-download endpoints be in scope? → A: Yes
  — include them as a "file download" kind alongside HTML pages, with their own
  content type, note, tag, and flag.
- Q: Should implicit HTML rendering (an action with no `render` line whose only
  locatable view is an HTML file) be classified as an HTML page? → A: Yes — keep
  implicit rendering in scope; it catches server-rendered pages that have no
  `render` line.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Tell non-JSON endpoints apart from JSON APIs (Priority: P1)

A developer's application mixes JSON API endpoints with routes that render HTML
pages (admin screens, editor pages, server-rendered views) and routes that send
file downloads. When the document is generated, every endpoint that returns a
non-JSON response — an HTML page or a file download — is visibly distinguished
from the JSON endpoints, so a reader of the documentation immediately knows
which endpoints are not part of the JSON API.

**Why this priority**: Without this, page- and download-rendering routes sit in
the document looking like JSON endpoints with empty/odd responses — misleading
and noisy. Making them visibly distinct is the core value of the feature.

**Independent Test**: Generate the document for an application that has an
HTML-page action, a file-download action, and a JSON action, and confirm the
HTML-page and download operations are clearly marked and grouped separately
while the JSON operation is untouched.

**Acceptance Scenarios**:

1. **Given** an action that renders an HTML page, **When** the document is
   generated, **Then** that operation's success response is presented as an
   HTML response rather than a JSON response with a body schema.
2. **Given** an action that sends a file download, **When** the document is
   generated, **Then** that operation's success response is presented as a
   file-download response rather than a JSON response with a body schema.
3. **Given** an HTML-page or file-download action, **When** the document is
   generated, **Then** the operation's description carries a note stating which
   kind it is (naming the page/template where known).
4. **Given** HTML-page and file-download actions exist, **When** the document is
   generated, **Then** those operations are grouped under dedicated tags,
   separate from the JSON endpoints.
5. **Given** an action that renders JSON, **When** the document is generated,
   **Then** it is NOT marked as an HTML page or a file download and its response
   is unchanged.

---

### User Story 2 - Programmatically identify non-JSON endpoints (Priority: P2)

A developer wants tooling — a filter, a linter, a doc post-processor — to find
or exclude non-JSON endpoints without parsing prose. When the document is
generated, each HTML-page and file-download operation carries a machine-readable
flag identifying its kind.

**Why this priority**: The visible marks (Story 1) serve human readers; a
structured flag serves automation. It builds on Story 1's detection but adds
value only once detection exists.

**Acceptance Scenarios**:

1. **Given** an HTML-page or file-download operation, **When** the document is
   generated, **Then** the operation carries a machine-readable flag identifying
   its kind, including the page/template name when known.
2. **Given** a JSON endpoint, **When** the document is generated, **Then** it
   does not carry that flag.

---

### User Story 3 - See how many endpoints are pages/downloads, not APIs (Priority: P3)

When the document is generated, the run report summarizes how many endpoints
render HTML pages and how many send file downloads, so the developer can gauge
how much of the route set is non-API at a glance.

**Why this priority**: A useful at-a-glance metric, but secondary to actually
marking the endpoints.

**Acceptance Scenarios**:

1. **Given** generation completes, **When** the developer reads the run report,
   **Then** it states how many endpoints were classified as HTML pages and how
   many as file downloads.

---

### Edge Cases

- **JSON render wins**: An action with both a happy-path `render json:` and an
  HTML or download signal is treated as a JSON endpoint — the JSON response is
  authoritative.
- **Implicit HTML render**: An action with no explicit render whose only view is
  an HTML template (no JSON view) is classified as an HTML page.
- **Explicit template render**: An action that renders a named HTML template
  belonging to another controller is classified as an HTML page, and the note
  names that template.
- **File download**: An action that calls `send_file` or `send_data` is
  classified as a file-download endpoint.
- **Undeterminable**: An action with no JSON render, no HTML signal, no download
  signal, and no locatable view stays undeterminable (unchanged from current
  behavior) — it is NOT guessed to be an HTML page or download.
- **Unlocatable template**: An action renders a named template that cannot be
  located; classification falls back to undeterminable rather than guessing.
- **Path parameters / summaries**: An HTML-page or file-download operation still
  keeps its path, path parameters, summary, description, source reference, and
  operation id.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST classify each controller action as one of: a JSON
  endpoint, an HTML-page endpoint, a file-download endpoint, or undeterminable.
- **FR-002**: The system MUST detect HTML rendering from these static signals:
  an explicit render of a template/action that resolves to an HTML view file;
  an implicit render whose only locatable view is an HTML view file (with no
  JSON view); and an explicit `render html:` of inline HTML.
- **FR-003**: The system MUST detect a file-download endpoint from a `send_file`
  or `send_data` call in the action body.
- **FR-004**: A happy-path JSON render MUST take precedence — an action that
  renders JSON is classified as a JSON endpoint even if an HTML view or download
  signal also exists; it MUST NOT be marked as an HTML page or file download.
- **FR-005**: For an HTML-page endpoint, the system MUST present the success
  response with an HTML content type; for a file-download endpoint, with a
  file-download (binary) content type. In both cases there MUST be no JSON body
  schema.
- **FR-006**: For an HTML-page or file-download endpoint, the system MUST add a
  note to the operation description identifying its kind and naming the
  page/template when that name is known.
- **FR-007**: The system MUST group HTML-page operations under an "HTML Pages"
  tag and file-download operations under a "File Downloads" tag, in addition to
  their controller tag, so documentation viewers collect them into separate
  sections.
- **FR-008**: The system MUST add a machine-readable flag to each HTML-page and
  file-download operation, identifying its kind and including the page/template
  name when known.
- **FR-009**: The system MUST NOT add the non-JSON marks (response type, note,
  tag, flag) to endpoints classified as JSON or as undeterminable.
- **FR-010**: An action whose classification cannot be determined MUST retain
  its current behavior (undeterminable response) and MUST NOT be guessed to be
  an HTML page or a file download.
- **FR-011**: Classification MUST rely only on static inspection — no controller
  action is executed and no HTTP request is made.
- **FR-012**: Generation MUST remain deterministic and the generated document
  MUST continue to pass OpenAPI schema validation.
- **FR-013**: The feature MUST be additive — routes, parameters, summaries,
  descriptions, source references, controller tags, and JSON response bodies of
  JSON endpoints MUST be unchanged.
- **FR-014**: The system MUST report, in the run summary, the number of
  endpoints classified as HTML pages and the number classified as file
  downloads.

### Key Entities *(include if feature involves data)*

- **Non-JSON Endpoint**: An endpoint classified as returning a non-JSON
  response. It has a kind — "HTML page" or "file download".
- **Render Classification**: The outcome of inspecting an action — one of
  "JSON", "HTML page", "file download", or "undeterminable".
- **Page Reference**: The name of the HTML template/page an action renders, when
  it can be determined; surfaced in the description note and the machine-readable
  flag.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% of endpoints whose actions render an HTML page or send a file
  download are marked as the corresponding non-JSON kind in the generated
  document.
- **SC-002**: 0% of JSON endpoints are misclassified as HTML pages or file
  downloads.
- **SC-003**: Every non-JSON operation carries all four marks: a non-JSON
  response content type, a description note, the kind's tag, and the
  machine-readable flag.
- **SC-004**: A reader of the generated documentation can, without reading
  application source, identify which endpoints render pages, which send
  downloads, and which serve JSON.
- **SC-005**: The generated document continues to pass OpenAPI schema
  validation, and repeated runs on unchanged input produce identical output.
- **SC-006**: The run report states the count of HTML-page endpoints and the
  count of file-download endpoints.

## Assumptions

- "HTML page" means an endpoint that responds with a rendered HTML document;
  "file download" means an endpoint that responds with file/binary content via
  `send_file`/`send_data`. Both are in scope; other non-HTML, non-JSON responses
  remain out of scope and keep their current behavior.
- Implicit rendering counts: an action with no explicit render statement whose
  only locatable view is an HTML view file is classified as an HTML page. This
  is intentional, to catch server-rendered pages that have no `render` line.
- A happy-path `render json:` always wins over an HTML or download signal (an
  action does not both return JSON and render a page/download as its success
  response).
- The "HTML Pages" / "File Downloads" tags are added alongside — not instead of
  — the existing per-controller tag, so a non-JSON operation appears in both
  groupings.
- This feature builds on the existing generated document; it changes only the
  classified non-JSON operations and the run report.
- Error/alternate responses remain out of scope (consistent with the
  happy-path-only scope of response bodies).
