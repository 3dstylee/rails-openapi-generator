# Phase 0 Research: HTML Page & File Download Endpoints

## R1. Detecting HTML rendering

**Decision**: An action is an HTML-page endpoint when any of these static
signals holds, and no happy-path `render json:` is present:

1. **`render html:`** — an explicit `render` with an `html:` option (inline HTML).
2. **Explicit template render** — `render :action`, `render "path"`, or
   `render template: "path"` whose target resolves to an HTML view file.
3. **Implicit HTML view** — the action has no explicit render and its
   conventional view path resolves to an HTML view file but not a
   `.json.jbuilder` file.

An "HTML view file" is one whose name ends in `.html.<engine>` —
`.html.erb`, `.html.haml`, `.html.slim` are recognized; the match is on the
`.html.` segment so any templating engine qualifies.

**Rationale**: These cover the ways a Rails action serves HTML. Implicit
rendering is included per the `/speckit-clarify` decision — most server-rendered
pages have no `render` line. All three signals are resolved by AST inspection
plus view-file existence checks, never by executing code (FR-011).

**Alternatives considered**:
- *Explicit renders only*: rejected during `/speckit-clarify` — would miss the
  majority of page endpoints.
- *Inspecting view content*: unnecessary — the `.html.` filename is sufficient.

## R2. Detecting file downloads

**Decision**: An action is a file-download endpoint when its body contains a
`send_file` or `send_data` call (and no happy-path `render json:`).

**Rationale**: `send_file`/`send_data` are the standard Rails ways to stream a
file/binary response. `RenderExtractor` already has a generic
`render_calls(node, name)` AST scan; detecting `send_file`/`send_data` reuses it
directly.

**Alternatives considered**:
- *Treating downloads as a flavor of HTML page*: rejected — a download is not a
  page; it warrants its own content type, tag, and flag (the `/speckit-clarify`
  answer chose a distinct "file download" kind).

## R3. Classification precedence

**Decision**: `RenderClassifier` applies signals in this fixed order:

1. Happy-path `render json:` present → **JSON** (FR-004 — JSON always wins).
2. `send_file` / `send_data` present → **file download**.
3. `render html:` present → **HTML page**.
4. Explicit template render → resolve the target view file:
   `.json.jbuilder` → **JSON**; `.html.*` → **HTML page**.
5. Implicit view lookup → `.json.jbuilder` exists → **JSON**;
   only `.html.*` exists → **HTML page**.
6. None of the above → **undeterminable**.

**Rationale**: A deterministic, single-pass precedence yields one classification
per action. JSON-first honors FR-004. Putting `send_file` before `render html:`
is arbitrary-but-fixed; an action realistically has one of them.

## R4. View resolution (`ViewLocator`)

**Decision**: `ViewLocator` exposes one resolution method that, for a route +
action, returns the matching view file **and its kind** (`:json` or `:html`),
or nil. It checks an explicitly rendered template name first, then the Rails
convention path, testing `.json.jbuilder` before `.html.<engine>`.

**Rationale**: The classifier needs to know both *whether* a view exists and
*which kind* it is. Returning kind + path from one method keeps the lookup
single-pass and reuses the convention/explicit logic already in `ViewLocator`.

## R5. OpenAPI representation of the four marks

**Decision**:

| Mark | HTML page | File download |
|------|-----------|---------------|
| Response content | `text/html` with `{ "type": "string" }` schema | `application/octet-stream` with `{ "type": "string", "format": "binary" }` |
| Description note | `_Renders an HTML page (\`<template>\`)._` | `_Sends a file download._` |
| Tag | `HTML Pages` (plus the controller tag) | `File Downloads` (plus the controller tag) |
| Vendor extension | `x-renders-html: true` (+ `x-html-template: "<name>"` when known) | `x-sends-file: true` |

**Rationale**: `text/html` / `application/octet-stream` are the correct OpenAPI
content types. The note format mirrors feature 002's `_Source: …_` convention so
descriptions stay consistent. Separate tags keep the two kinds in distinct
viewer sections (FR-007). `x-` extensions are the OpenAPI-sanctioned way to add
machine-readable metadata; the names match the user's stated preference for
HTML and extend the same pattern for downloads.

**Alternatives considered**:
- *A single `x-response-kind` enum*: cleaner in theory, but the user explicitly
  asked for `x-renders-html`; the parallel `x-sends-file` keeps it predictable.

## R6. Status code

**Decision**: Keep the existing method-based status mapping from feature 002
(GET/PUT/PATCH→200, POST→201, DELETE→204). HTML pages and downloads are almost
always GET → 200.

**Rationale**: Consistent with the response-bodies feature; no reason to special-
case status for non-JSON kinds.

## R7. Reporting

**Decision**: `GenerationReport` gains two counters — HTML-page endpoints and
file-download endpoints — incremented by `Generator` as it classifies, and
printed in the run summary.

**Rationale**: Satisfies FR-014/SC-006 with a minimal additive change to the
existing report object.

## Resolved unknowns

All Technical Context items are resolved. No new runtime dependency. No
`NEEDS CLARIFICATION` markers remain — the two scope questions (file downloads,
implicit HTML rendering) were settled in `/speckit-clarify`.
