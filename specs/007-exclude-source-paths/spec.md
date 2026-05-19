# Feature Specification: Exclude Endpoints by Source Path

**Feature Branch**: `007-exclude-source-paths`

**Created**: 2026-05-19

**Status**: Draft

**Input**: User request: add a configuration option to exclude endpoints by
their controller source file path. A new `exclude_source_paths` setting takes a
list of strings (substring match) and/or regexps; any route whose resolved
controller source file matches an entry is omitted from the generated document
and recorded as skipped in the run report. Complements the existing
`route_filter` by filtering on where the controller is defined.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Exclude endpoints by a source-path substring (Priority: P1)

A developer wants the generated document to cover only their own application
code, not controllers that live elsewhere — for example controllers under a
`vendor/` directory. They configure a list of path substrings to exclude; any
endpoint whose controller source file path contains one of them is left out of
the document.

**Why this priority**: This is the core value — the developer can scope the
document to the controllers they care about, by where the code lives, which the
existing route filter (which sees only the route, not the source file) cannot
do.

**Independent Test**: Configure an exclusion for a path substring, generate the
document for an application with a controller whose source file is under that
path, and confirm that controller's endpoints are absent from the document and
listed as skipped in the run report.

**Acceptance Scenarios**:

1. **Given** `exclude_source_paths` contains `"vendor/"`, **When** the document
   is generated, **Then** endpoints whose controller source file path contains
   `vendor/` are omitted from the document.
2. **Given** an endpoint is excluded by a source-path substring, **When** the
   document is generated, **Then** the run report records it as skipped, with a
   reason naming the matched exclusion.
3. **Given** `exclude_source_paths` is empty or unset, **When** the document is
   generated, **Then** no endpoint is excluded on the basis of its source path.
4. **Given** a controller whose source file does NOT match any exclusion entry,
   **When** the document is generated, **Then** its endpoints are still
   documented.

---

### User Story 2 - Exclude endpoints by a regexp pattern (Priority: P2)

A developer needs a more precise match than a plain substring — for instance,
excluding controllers in a specific nested location. They include a regular
expression in `exclude_source_paths`; any endpoint whose controller source file
path matches the pattern is excluded.

**Why this priority**: Substring matching (Story 1) handles the common case;
regexp entries cover the cases where a substring is too broad or too narrow.

**Acceptance Scenarios**:

1. **Given** `exclude_source_paths` contains a regexp, **When** the document is
   generated, **Then** endpoints whose controller source file path matches the
   regexp are omitted.
2. **Given** a list containing both a string and a regexp entry, **When** the
   document is generated, **Then** an endpoint is excluded if it matches either.

---

### Edge Cases

- **Unresolvable controller source**: A route whose controller source file
  cannot be located is not affected by source-path exclusion (it has no path to
  match); it keeps its current behavior.
- **Empty / unset list**: No source-path exclusion is applied.
- **Both filters configured**: `exclude_source_paths` and the existing
  `route_filter` both apply — an endpoint is excluded if either drops it.
- **Invalid entry**: An `exclude_source_paths` entry that is neither a string
  nor a regexp causes the configuration to be rejected before generation.
- **All endpoints excluded**: If every endpoint is excluded, a valid but empty
  document is still produced.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST provide an `exclude_source_paths` configuration
  setting that accepts a list of exclusion entries.
- **FR-002**: Each entry MUST be either a string or a regular expression; a
  string entry matches when it is a substring of the controller source file
  path, a regexp entry matches when it matches the path.
- **FR-003**: The system MUST omit from the generated document every endpoint
  whose resolved controller source file path matches any `exclude_source_paths`
  entry.
- **FR-004**: The system MUST record each source-path-excluded endpoint as
  skipped in the run report, with a reason indicating it matched a source-path
  exclusion.
- **FR-005**: Source-path exclusion MUST apply only when a controller source
  file has been resolved; a route with no resolvable source is unaffected.
- **FR-006**: When `exclude_source_paths` is empty or unset, the system MUST NOT
  exclude any endpoint on the basis of its source path (default behavior
  unchanged).
- **FR-007**: Source-path exclusion MUST work alongside the existing
  `route_filter`; an endpoint is excluded if either mechanism drops it.
- **FR-008**: The system MUST reject an `exclude_source_paths` value that is not
  a list, or that contains an entry that is neither a string nor a regexp,
  before generation begins.
- **FR-009**: Generation MUST remain deterministic and the generated document
  MUST continue to pass OpenAPI schema validation.

### Key Entities *(include if feature involves data)*

- **Exclusion Pattern**: A single `exclude_source_paths` entry — a string
  (substring match) or a regular expression — tested against a controller
  source file path.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: An endpoint whose controller source file path matches an
  `exclude_source_paths` entry does not appear in the generated document.
- **SC-002**: An endpoint whose controller source file path matches no entry
  still appears in the generated document.
- **SC-003**: Every source-path-excluded endpoint is listed as skipped in the
  run report.
- **SC-004**: With `exclude_source_paths` empty or unset, the generated document
  is identical to what it was before this feature.
- **SC-005**: An invalid `exclude_source_paths` value is reported as a
  configuration error before any document is generated.
- **SC-006**: Generated documents continue to pass OpenAPI schema validation,
  and repeated runs on unchanged input produce identical output.

## Assumptions

- The match is performed against the absolute path of the resolved controller
  source file; a string entry such as `"vendor/"` matches anywhere in that path.
- `exclude_source_paths` defaults to an empty list — no exclusion — so existing
  documents are unchanged unless the setting is configured.
- A source-path-excluded endpoint is reported the same way other skipped routes
  are (in the run report's skipped list), keeping one consistent reporting path.
- This feature builds on the existing generated document; it only removes
  endpoints whose controller source matches a configured pattern.
