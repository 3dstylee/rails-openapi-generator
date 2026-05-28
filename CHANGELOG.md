# Changelog

All notable changes to this gem are documented here. This project follows
[Semantic Versioning](https://semver.org/).

## [0.25.0] - 2026-05-28

### Fixed

- Schema sidecars that use JSON Schema `$defs` with internal
  `#/$defs/<name>` references now produce a valid OpenAPI document.
  Previously the sidecar was inlined verbatim deep inside the document,
  leaving its document-root-relative refs pointing at a `$defs` block
  that no longer existed at the OpenAPI root — so tools like Redocly
  failed with `Invalid reference token: $defs`.
- Each sidecar's `$defs` are now hoisted into `components/schemas` and
  every `#/$defs/<name>` ref is rewritten to
  `#/components/schemas/<key>`. Identical definitions from separate
  sidecars share one component key; a same-named but differently-shaped
  definition is suffixed (e.g. `transit_item_2`) so distinct types are
  never merged.

## [0.24.0] - 2026-05-21

### Added

- `param!` declarations now support a `description:` option that
  surfaces in the OpenAPI output:
  - For **query / path** parameters, the description is emitted at
    the OpenAPI Parameter Object level (the canonical location doc
    viewers like Swagger UI / Redoc / Scalar render).
  - For **request body** properties (top-level under POST/PUT/PATCH
    and any nested `param!` block), the description is emitted on
    the property's schema — the canonical location for body-field
    documentation in OpenAPI 3.1.
- Example:
  ```ruby
  param! :query, String, blank: false,
    description: "Free-text search across name and email"
  ```
  produces:
  ```json
  { "name": "query", "in": "query", "required": false,
    "description": "Free-text search across name and email",
    "schema": { "type": "string", "minLength": 1 } }
  ```
- Non-String `:description` values are ignored (no schema/parameter
  field emitted). Operations without `:description` on any
  `param!` emit byte-identical output to `0.23.0`.

## [0.23.0] - 2026-05-21

### Added

- `param!` now recognizes rails-param's symbol-form type shorthand
  `:boolean` (e.g. `param! :downloadable, :boolean, required: true`)
  and emits `{type: boolean}` in the requestBody schema. Previously
  the symbol form was unresolvable and the parameter fell back to
  `{type: string}` (DEFAULT_SCHEMA). Class-form types
  (`Boolean`, `TrueClass`, `FalseClass`) were already recognized;
  this brings the symbol shorthand to parity. Easy to extend if more
  symbol shorthands surface (`:bool`, `:int`, etc.).

## [0.22.0] - 2026-05-20

### Fixed

- `json.partial! "name"` and `json.array! @c, partial: "name"` with a
  **bare** (unqualified) partial name now resolve relative to the
  caller's directory first — matching Rails' own partial-resolution
  convention. Previously, only slash-qualified names like
  `"api/users/user"` were resolvable, and bare names silently failed
  to find the partial (the schema degraded to permissive `{}`).
  Slash-qualified names continue to resolve against `views_root`
  exactly as before.
- This unblocks the feature 020 sidecar mechanism for real-world
  templates that use Rails' relative partial convention — every
  `_partial.schema.json` next to a `_partial.json.jbuilder` now
  surfaces whether the consumer references the partial by bare name
  or full path.

## [0.21.0] - 2026-05-20

### Added

- Primitive literal values in jbuilder templates and inline
  `render json:` hashes now carry an OpenAPI `example` alongside
  the inferred type:
  - `json.role "member"` → `{type: string, example: "member"}`
  - `json.id 42` → `{type: integer, example: 42}`
  - `json.price 9.99` → `{type: number, example: 9.99}`
  - `json.active true` → `{type: boolean, example: true}`
  - `json.tags ["a", "b"]` → `{type: array, items: {type: string,
    example: "a"}, example: ["a", "b"]}`
- Composite literal renders (`render json: { ... }`, nested
  `json.x do ... end` blocks) recurse: every literal leaf gets its
  own `example`.
- Non-literal expressions (`json.id user.id`) remain permissive
  (`{}`) — no example, no change from `0.20.0`.
- Sidecar JSON Schema files (feature 020) are loaded verbatim, so
  a sidecar's `example` (or its absence) overrides the inferred one.

### Changed

- Operations with literal values in templates / inline renders gain
  `example` keys in their response schemas. Output is **not**
  byte-identical to `0.20.0` for these operations (additive — the
  `type` and field structure are unchanged, and the result remains
  valid OpenAPI 3.1).

## [0.20.0] - 2026-05-20

### Added

- **JSON Schema sidecar files** — a `.schema.json` file sitting next
  to a jbuilder template (or at the action's conventional view path)
  declares the response schema directly, overriding the parser's
  inference. Standard JSON Schema (Draft 2020-12). The convention:
  - Partial sidecar: `_user.schema.json` next to
    `_user.json.jbuilder` — used wherever `partial: "users/user"`
    resolves.
  - Action-template sidecar: `<action>.schema.json` next to
    `<action>.json.jbuilder`.
  - Inline-render / no-view action sidecar:
    `<controller>/<action>.schema.json` at the conventional view
    path even when no `.json.jbuilder` exists — overrides the
    body for the HTTP-method convention status entry.
- Sidecars are loaded once per path and cached for the run.
  Malformed sidecars (invalid JSON) emit a `Report` warning naming
  the file and fall back to the inferred schema; the generator
  never raises.
- Operations and partials without sidecars emit byte-identical
  output to `0.19.0`.

## [0.19.0] - 2026-05-20

### Fixed

- A `json.<key>` line in a jbuilder template guarded by
  **modifier-`if`** or **modifier-`unless`** (e.g.
  `json.errors @errors if @errors.present?`) is now included in
  the schema. Previously the parser returned the modifier's
  CONDITION node — not the guarded statement — as the branch body,
  so the guarded line was silently dropped from the resulting
  schema. The fix is a one-line correction in
  `JbuilderParser#conditional_bodies`. Templates without modifier
  conditionals emit byte-identical schemas to `0.18.0`.

## [0.18.0] - 2026-05-20

### Added

- Receiverless helper methods called from an action now receive
  **argument propagation**: literal positional and keyword arguments
  at the call site are bound to the helper's parameters and
  substituted into the helper body before render extraction. A
  controller that centralizes error rendering in a helper like
  `render_error(message, status_code, status)` and calls it as
  `render_error("oops", 422, :unprocessable_entity)` now documents
  the 422 entry (previously dropped because `status:` resolved to
  the unsubstituted parameter reference). Bindings compose through
  multi-level helper chains, are bounded by
  `method_resolution_depth` (default 5), and apply equally inside
  `before_action` callbacks and `rescue_from` handlers.
- Non-literal arguments leave the corresponding parameter unbound;
  references to it stay permissive, matching existing posture.
- Operations whose helpers contain no parameter-dependent render
  sites emit byte-identical output to `0.17.0`.

## [0.17.0] - 2026-05-20

### Fixed

- An action with no own response signal (no `render`, no `head`, no
  `redirect_to`, no resolvable view) but with extras contributing
  only error-status entries (typically `rescue_from`) now documents
  a body-less entry at the HTTP-method convention status
  (200/201/204) alongside those error entries. Previously the
  operation lost its happy-path entry entirely, documenting only
  the rescue's 4xx/5xx statuses — which misrepresents Rails'
  runtime behavior (an implicit empty response on the happy path).
- Operations whose action source contributes any render site
  (`render :template`, `head :ok`, `render json:`, inline render)
  emit byte-identical output to `0.16.0` — the new branch fires
  only in the "no action signal + non-empty extras" gap.

## [0.16.0] - 2026-05-20

### Added

- jbuilder parser now recovers the schema shape from two more
  template patterns that previously degraded to a permissive `{}`:
  - `json.<key> @collection, partial: "name", as: :name` resolves
    the partial recursively and emits
    `{type: array, items: <partial schema>}`. The single-object
    form (`json.user partial: "user"`) inlines the partial's
    schema directly. The existing cycle guard prevents infinite
    recursion if a partial refers back to its own template. When a
    block is given alongside `partial:`, the block wins (matches
    jbuilder's runtime semantics).
  - `case` / `when` / `else` branches now merge into one schema
    the same way `if` / `elsif` / `else` already does — every
    branch's properties are unioned (last-wins for duplicate
    keys, all unique keys preserved). Templates without these
    shapes emit byte-identical schemas to `0.15.0`.

## [0.15.0] - 2026-05-20

### Changed

- The `"<METHOD> <PATH>: response shape could not be determined"`
  warning is no longer emitted for controller actions that produce
  no static response signal — no `render`, no `head`, no
  `redirect_to`, no `respond_to`, no resolvable view template, and
  no contributing render sites from helpers / `before_action` /
  `rescue_from`. Rails returns an implicit empty response at
  runtime for these actions, so the warning was firing on noise
  rather than on actionable issues.
- The OpenAPI document output for these operations is unchanged
  (still a body-less entry at the HTTP-method convention status —
  200 / 201 / 204). The internal `Response#undeterminable?`
  predicate now returns `false` for the no-signal case; the
  Generator's warning emit is gated on that predicate, so the
  warning naturally stops firing.

### Trade-off

- Serializer-based responses (Blueprinter, ActiveModelSerializer,
  etc.) fall through the same path because the generator cannot
  see their bodies statically. They previously fired the warning;
  they now don't. Users who rely on the warning to spot
  serializer gaps should track those endpoints by other means
  (e.g. a per-controller convention). A future feature can add
  explicit serializer detection if needed.

## [0.14.0] - 2026-05-20

### Added

- `rescue_from` declarations on the controller class chain are now
  detected and each handler's renders are documented as response
  entries on every action in the controller. For an
  `ApplicationController` that declares 3–5 handlers (for
  `RecordNotFound`, `NotAuthorizedError`, `ParameterMissing`,
  `RecordInvalid`, etc.), every operation on every inheriting
  controller gains 3–5 additional response entries — each with the
  handler's literal body shape and explicit status.
- Both method-form (`rescue_from FooError, with: :method_name`) and
  block-form (`rescue_from FooError do |e| render ... end`) handlers
  are walked. Block-form resolution uses `proc.source_location` plus
  a targeted Ripper AST search.
- Handlers declared inside concerns mixed into the controller (or
  any ancestor) are included automatically — `rescue_handlers`
  merges the chain.
- Constant resolution and template-render walking inside handler
  bodies inherit from features 011 / 013 for free (no new wiring):
  a handler doing `render json: { error: "..." }, status:
  Constants::FORBIDDEN_STATUS` resolves the constant via the
  existing pipeline.
- A handler whose target method cannot be resolved (e.g. defined
  in a gem) is silently skipped; the generator never raises.
- A new internal `RescueFromResolver` class (one method:
  `resolve(controller_class)`) caches per-class results for the
  generator run.

### Changed (additive)

- Operations on controllers whose entire class chain has no
  `rescue_from` declarations emit byte-identical output to
  `0.13.0`. The new walker only activates when
  `controller.rescue_handlers` is non-empty (SC-004).

### Fixed

- An action with no inline render but backed by a jbuilder view, on
  a controller inheriting from a base with `rescue_from`
  declarations, no longer loses its happy-path `200` entry to the
  inherited error-status entries. The view's schema is now
  integrated into the convention-status entry even when extras
  (rescue_from, before_action, helpers) populate other statuses.
  This bug existed since `0.9.0` for any case where extras
  produced ≥ 2 entries; feature `0.14.0` made it visible at scale
  because rescue_from typically inherits 3–5 entries.

### Out of scope (deferred to a future feature)

- Re-raising handlers — we don't follow the re-raise chain.
- Handlers that delegate to `Rails.error.handle` /
  `ActiveSupport::ErrorReporter`.
- Non-literal `status:` values (e.g. `status: error.status_code`)
  — dropped per existing literal-only resolution rules.
- Exception-implied statuses without an explicit `rescue_from`
  (e.g. `find!` → `RecordNotFound` without a corresponding
  handler).
- Surfacing the rescued exception class name in the OpenAPI doc
  — only the handler's status and body shape are documented.

## [0.13.0] - 2026-05-20

### Added

- `param! :name, Hash do |q| ... end` and `param! :name, Array do |a, i|
  ... end` block forms are now walked. Nested `<blockvar>.param! ...`
  calls inside the block become the parent's nested schema:
  - `Hash` with a block → `{type: object, properties: {...}}` with
    each nested `param!` documented as a property.
  - `Array` with a block → `{type: array, items: <child schema>}`
    using the (single) item declaration.
- Nested constraint mapping reuses the existing flat-`param!` rules:
  `in:`, `required:`, `min:`/`max:`, `format:`, etc. Combined with
  feature 013, a nested `in: Module::CONSTANT` resolves the constant
  and emits the actual `enum:` on the items schema — closing the
  full user-reported case (`param! :moods, Array do |p, i| p.param!
  i, String, in: Module::MOODS end`).
- Recursion is bounded by the existing
  `Configuration#method_resolution_depth` setting (default 5).
  Subtrees beyond the bound fall back to a bare object/array schema
  and the generator completes successfully.

### Changed (additive)

- Operations whose `param!` calls have no block (or have a block on
  a non-Hash/Array type) emit byte-identical output to `0.12.0` —
  the new walker only activates when a `Hash`/`Array` `param!` has
  a do-block.
- `BeforeActionResolver#own_source_file` now prefers
  `Module.const_source_location` over the first-method
  source_location heuristic. The previous heuristic depended on
  `instance_methods(false)` ordering, which is not strictly
  guaranteed across autoload reloads; the new lookup is stable.
  This fixes a sporadic failure to recover `only:` / `except:`
  literal-array filters when running large test suites.

### Out of scope (deferred to a future feature)

- The OpenAPI object-level `required:` array on nested objects —
  per-property `required: true` flags are documented within each
  property; lifting them to a parent-object `required:` list is
  out of scope.
- Heterogeneous array `items:` (`oneOf: [...]`) — only the last
  item declaration in source order is used.
- Block-on-non-Hash/Array types — silently ignored.

## [0.12.0] - 2026-05-20

### Added

- Constant references used as `param!` argument values are now
  resolved at generation time and emitted into the parameter
  schema. `param! :mood, String, in: Module::CONSTANT` where the
  constant is a literal Array of Strings now documents
  `enum: [...]` with the actual values. Resolution covers three
  AST shapes: bare constants (`FOO`), qualified paths
  (`A::B::CONST`), and top-level references (`::Foo`).
- The "non-literal param! arguments for X" warning is no longer
  emitted for a parameter whose only previously-unresolved
  argument was a schema-compatible constant reference.
- The "schema-compatible" set is intentionally narrow: primitives
  (`String`, `Symbol`, `Integer`, `Float`, `true`, `false`),
  `Array` of recursively-compatible elements, `Hash` with
  `String`/`Symbol` keys and recursively-compatible values,
  `Range` of `Integer` or `Float` ends, and `Regexp`. Other
  values (class references, Procs, instances, mixed-numeric
  Ranges, etc.) are treated as unresolved.
- `Object.const_get(name, true)` is used for the lookup — with
  autoload — so constants in yet-untouched files are loaded on
  demand the same way Rails resolves a class name. Any
  `StandardError` or `LoadError` is silently treated as
  unresolved; the generator never raises because of this feature.
- Resolution is cached per generator run; the same qualified
  name triggers at most one `const_get` call.
- `SchemaMapper#apply_constraints` now also accepts a `Regexp`
  value for `:format` (the existing String form continues to
  work) — needed because a Regexp constant resolves to a Regexp
  object, not its source String.

### Known limitation

- `param!` calls nested inside a block (feature 008's
  `param! :things, Array do |p, i|; p.param! i, ...; end`
  pattern) are not walked by today's `ParamExtractor`, so a
  constant referenced inside such a nested block does NOT yet
  emit its `enum` on the inner items schema. Feature 013's
  constant resolution covers the top-level `param!` case (the
  primary motivating shape); the nested case unblocks once
  feature 008 is implemented (no additional work in feature
  013 will be required — the resolver already runs through the
  same evaluator).

### Changed (additive)

- Operations whose `param!` calls have always been fully literal
  in the source emit byte-identical output to `0.11.0`. The new
  evaluator paths fire only when the AST contains a
  constant-reference node.

### Out of scope (deferred to a future feature)

- Constant references outside `param!` calls — `redirect_to`,
  `render`, `respond_to`, etc.
- Constants assigned inside controller actions.
- Constants resolved through a method chain (`Service.new.X` —
  not a constant reference).

## [0.11.0] - 2026-05-20

### Added

- `respond_to do |format| ... end` blocks are now detected in the
  action body, helper methods, and `before_action` callbacks. Each
  `format.<symbol>` call inside the block contributes a content-type
  entry to the operation's response set:
  - `format.json` → `application/json` (schema from the action's
    default `.json.jbuilder`, or from an inline `render json:` inside
    the format block).
  - `format.html` → `text/html` (the existing HTML-page placeholder
    schema, or from an inline render inside the format block).
- When both `format.json` AND `format.html` apply at the same status,
  the operation's response carries BOTH content types under one
  OpenAPI response entry — the standard OpenAPI 3.1 multi-content-
  type shape:
  ```yaml
  '200':
    description: Successful response
    content:
      application/json: { schema: { ... } }
      text/html:        { schema: { type: string } }
  ```
- An inline `render` call inside a `format.<symbol>` block overrides
  the default-view lookup for that format; the inline render's
  status, schema, and content type apply.
- Unknown format symbols (`format.xml`, `format.csv`, `format.pdf`,
  `format.any`, `format.all`) are silently ignored — they contribute
  no content type and the operation's classification is unchanged.

### Changed (additive)

- Content types within a single OpenAPI response entry are emitted
  in alphabetical order (`application/json` before `text/html`) for
  byte-stable output.
- Operations whose code does NOT contain a `respond_to` block emit
  byte-identical output to `0.10.0` — the new multi-content-type
  emission path activates only when a `respond_to` block contributes
  multiple content types at the same status.

### Out of scope (deferred to a future feature)

- `format.xml` / `format.csv` / `format.pdf` / other format symbols
  beyond `:json` and `:html`.
- `format.any` / `format.all` and dynamic dispatch (`format.send(...)`).
- `respond_to` calls without a block argument (invalid Rails syntax).

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
