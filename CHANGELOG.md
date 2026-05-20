# Changelog

All notable changes to this gem are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [0.10.0] - 2026-05-20

### Added

- Template renders — `render "path/to/template"`, `render :symbol`,
  `render template:`, `render action:` — reached through helper
  methods (including methods in concerns) and through `before_action`
  callbacks now contribute response sites the same way `render json:`
  and `head` calls do (feature 010). An action whose happy path is a
  `render "..."` call inside a private helper is now documented under
  the happy status with the resolved jbuilder schema, alongside any
  error-status entries from JSON renders in the action body.
- An explicit `formats:` option on a `render` is honored when the
  value is a literal Symbol or a literal Array of Symbols:
  `formats: :json` → look up `.json.jbuilder`; `formats: :html` → look
  up `.html.*`; `formats: [:json, :html]` → try each in order. When
  the requested format's view does not exist, the site contributes a
  body-less entry under its resolved status (better than today's
  silent drop). When the option is absent or non-literal, the
  existing "prefer JSON over HTML" lookup applies.
- An action whose only renders are HTML-template renders at a single
  status (no `render json:` anywhere reachable) classifies as
  `:html_page` (single-entry response with `text/html` content), even
  when the template render lives in a helper or a `before_action`.

### Changed (additive)

- Operations whose only render in `0.9.0` was a single action-body
  template render — a jbuilder-backed JSON action, or a single-page
  HTML action — emit byte-identical output. The change is purely
  additive at the per-operation level for any endpoint whose response
  set in `0.9.0` was already accurate.

### Out of scope (deferred to a future feature)

- `respond_to { |format| format.json { render ... } }` blocks.
- Dynamic dispatch (`send(name)`, `public_send(name)`).
- Non-literal `formats:` values (procs, instance variables, method
  calls).
- `render partial:` (a partial is not a complete response).
- Bare-status-symbol renders (`render :ok`) — today's
  "treat-as-template-name" behavior remains.

## [0.9.0] - 2026-05-20

### Added

- Operations whose action issues more than one `render json:` or `head`
  call are now documented with one OpenAPI response entry per HTTP
  status — not only the happy-path response. Each entry's body is the
  schema of the corresponding render (literal hashes resolve to a typed
  schema; non-literal values produce a body-less entry under the known
  status, which is still better documentation than today).
- `render json:` / `head` calls reached through receiverless helper
  methods called from the action body — including methods defined in
  concerns mixed into the controller — contribute to the operation's
  response set. Reuses the existing controller-method walker, so depth
  is bounded by `Configuration#method_resolution_depth`.
- `before_action` callbacks declared on the controller class (or
  inherited from parents and concerns) contribute to the operation's
  response set on a best-effort basis. `only: [...]` and `except: [...]`
  filters are honored when their value is a literal array of symbols;
  non-literal conditionals (`if: -> { ... }`) fall back to "applies to
  every action in the controller".
- When two renders share a status with distinct literal shapes, the
  entry's body is documented as an OpenAPI `oneOf` of the unique
  schemas, sorted by canonical JSON ascending for determinism. A `head`
  call's no-body contribution collapses into the render's body at the
  same status.

### Changed (additive)

- The `"response shape could not be determined"` warning no longer
  fires for an operation that has at least one statically-known status
  entry — even if every entry's body is non-literal. Actions with no
  render, no head, no redirect, and no resolvable view continue to
  emit the warning (unchanged).
- Internal `Response` shape: a `Response` now carries an ordered list
  of `entries: [ResponseEntry(status, body)]`. Single-status operations
  still emit byte-identical output to `0.8.0` (one entry → one
  response key). Library consumers reading `response.status` /
  `response.body` keep working — those forwarders read from the first
  entry.

### Out of scope (deferred to a future feature)

- `rescue_from` handlers and statuses implied by exception-raising
  calls (Pundit `authorize`, ActiveRecord `find!`, etc.) — modeling
  the exception → handler → status chain is app-specific and
  significant in scope.

## [0.8.0] - 2026-05-20

### Added

- An action whose success path is `redirect_to` (or `redirect_back` /
  `redirect_back_or_to`) is now documented as a redirect — the response is
  filed under the call's HTTP status code (`302 Found` by default, or the
  `status:` option if it resolves to a 3xx code) with no response body. This
  replaces the previous behavior, which fell through to "undeterminable" and
  documented the operation with the HTTP-method convention (e.g. `201` for a
  redirecting `POST`) plus a spurious `"response shape could not be
  determined"` warning.
- A short `_Redirects to another URL._` note is added to the operation's
  description, mirroring the existing HTML-page and file-download notes.

### Changed (additive)

- The `"response shape could not be determined"` warning is no longer emitted
  for actions whose only response statement is a redirect call. Actions with
  no render, no redirect, and no resolvable view continue to emit the warning
  (unchanged).
- Existing JSON / file-download / HTML-page / `head` responses are documented
  byte-identically to `0.7.0`. The change only affects endpoints whose
  previous documentation came from the wrong-status / undeterminable
  fallback.

## [0.7.0] - 2026-05-19

### Added

- New `exclude_source_paths` configuration setting — a list of strings
  (substring match) and/or regexps. Any endpoint whose resolved controller
  source file path matches an entry is omitted from the generated document and
  recorded as skipped in the run report. Useful for dropping vendored or
  third-party controllers. It complements `route_filter` (which filters by
  route); both apply.

### Changed (additive)

- With `exclude_source_paths` unset (the default empty list), output is
  unchanged — the feature is opt-in.

## [0.6.0] - 2026-05-19

### Added

- Request parameters used **implicitly** via the `params` object are now
  detected and documented — `params[:key]`, `params.require`, `params.permit`,
  `params.fetch`, `params.dig` — in the action body and, recursively, in the
  receiverless helper methods it calls. Discovered parameters are documented
  with a permissive ("any") schema.
- A key already documented via `rails_param` `param!` or as a path parameter
  keeps its definition; Rails-internal keys (`controller`, `action`, `format`)
  are never documented.

### Changed

- **Configuration**: `download_resolution_depth` is renamed to
  `method_resolution_depth` — it now bounds both wrapper-download resolution
  and implicit-params helper scanning. Same default (5).
- Operations gain newly discovered implicit parameters — additive; path
  parameters and `param!`-derived parameters are unchanged.

## [0.5.0] - 2026-05-19

### Added

- Each operation's success response is now filed under the status code the
  action **explicitly sets** — read from `head :symbol` / `head <integer>`
  calls and the `status:` option of `render` calls — instead of always being
  inferred from the HTTP method. A `head` response is documented body-less.
  Only happy-path (2xx/3xx) statuses are read; error-status guards are ignored.

### Changed (additive)

- An action that sets an explicit status now documents that status (e.g. a POST
  ending in `head :ok` is documented `200`, not `201`). Actions that set no
  explicit status keep the HTTP-method convention. Response kind, body, tags,
  and `x-` marks are unchanged.

## [0.4.0] - 2026-05-19

### Added

- File-download detection now resolves **wrapper methods**. An action that
  streams a file through a helper (e.g. `send_file_and_cleanup`) rather than
  calling `send_file`/`send_data` directly is still classified as a file
  download: the generator follows receiverless helper calls to their
  definitions — in the controller, an included concern, or a parent controller
  — recursively through chains of wrappers.
- Resolution is fully static, cycle-guarded, and bounded by a new
  `download_resolution_depth` configuration setting (default 5).

### Changed (additive)

- Some actions previously classified as undeterminable are now classified as
  file downloads. JSON, HTML-page, and direct-download classifications are
  unchanged.

## [0.3.0] - 2026-05-19

### Added

- Endpoints that render an **HTML page** or send a **file download** (rather
  than JSON) are now detected and marked: a non-JSON response content type
  (`text/html` / `application/octet-stream`), a description note, a dedicated
  tag (`HTML Pages` / `File Downloads`), and a vendor extension
  (`x-renders-html` + `x-html-template` / `x-sends-file`).
- The run report counts HTML-page and file-download endpoints.

### Changed (additive)

- Non-JSON endpoints' `responses`, `tags`, and `description` change to reflect
  their classification. JSON-endpoint output is unchanged — a `render json:`
  always takes precedence over an HTML view. Regenerate to pick up the marks.

## [0.2.1] - 2026-05-19

### Fixed

- When an action has multiple `render json:` calls, the response body is now
  taken from the happy-path render. Renders carrying an explicit error status
  (4xx/5xx) are skipped, so an early `render status: :bad_request, json: …`
  guard no longer masquerades as the success response.
- A response field whose value is not a literal (e.g. `json: { ids: some_var }`)
  is now documented with a permissive `{}` ("any") schema. It was previously
  mistyped as `"string"` because the internal unresolved-value sentinel is a
  Ruby Symbol.

## [0.2.0] - 2026-05-19

### Added

- Each operation's success response now carries a **response body schema**,
  derived statically from the action's jbuilder view template
  (`.json.jbuilder`) or a literal `render json:` call.
- Success responses are filed under a conventional status code: `200` for
  reads/updates, `201` for creation, `204` for deletion / `head :no_content`.
- Endpoints whose response shape cannot be determined are reported as warnings
  and still produce a valid (body-less) success response.

### Changed (breaking output change)

- The generated document's `responses` object changed for every operation:
  previously a fixed `{ "200": { "description": "Successful response" } }`
  placeholder, now a real status code with a `content`/`schema` body where one
  could be determined.

  **Migration**: regenerate the document (`rake openapi:generate`) and review
  the diff. Consumers and tooling that relied on the old placeholder `200`
  entry should expect `201`/`204` for creation/deletion operations and a
  populated response schema elsewhere. No configuration or API change is
  required — the new behavior is automatic.

## [0.1.0]

### Added

- Initial release: generate an OpenAPI 3.1 document from Rails routes,
  `rails_param` request validations, and YARD comments, via a rake task or CLI.
- Operations tagged by controller class; descriptions link to the action's
  source file and line.
