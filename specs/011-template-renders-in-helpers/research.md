# Phase 0 Research: Template Renders in Helpers

The spec carried no `[NEEDS CLARIFICATION]` markers. Decisions below
were resolved against the existing codebase, feature 010, and Rails
template-resolution semantics before writing the spec.

## R1. What counts as a template render

**Decision**: Four call shapes:
- `render "path/to/template"` — bare String positional, treated as a
  template path. If slash-qualified, used as-is; otherwise resolved
  relative to the route's controller (today's `ViewLocator` rule).
- `render :symbol` — bare Symbol positional, treated as a template
  named `<symbol>` relative to the route's controller.
- `render template: "path"` — explicit template path option (today's
  `template:` handling).
- `render action: :name` — explicit action name option (today's
  `action:` handling).

`render html:`, `render plain:`, `render text:`, `render file:`,
`render body:`, `render xml:` are explicitly **not** template renders
and remain handled as today. `render partial:` is out of scope
(FR-009 / Edge Cases).

**Rationale**: These four are the Rails public API for "render a
template by name". The existing `RenderExtractor#explicit_template_name`
already detects three of them; this feature generalizes that detection
to the multi-site model and across the walker.

**Alternatives considered**:
- *Also include `render partial:`*: a partial is a fragment of a view,
  not a complete response — documenting it as the operation's response
  would be wrong.
- *Detect `render :ok` as a status*: too ambiguous (Rails would treat
  it as a template name `:ok`); we keep today's interpretation (a
  Symbol positional is a template name).

## R2. How the `formats:` option is honored

**Decision**: When `render` carries a literal `formats:` option:
- `formats: :json` → request a `.json.jbuilder` lookup. If found, the
  site contributes a JSON site with the parsed jbuilder schema. If
  not found, the site contributes a body-less JSON site (status
  known, body unknown).
- `formats: :html` → request a `.html.*` lookup. If found, the site
  contributes an HTML-page site. If not found, the site contributes a
  body-less JSON site (consistent with FR-007's JSON-default kind for
  the "no view" case).
- `formats: [:json, :html]` (or any array) → try each format in order;
  the first format whose view exists wins. When neither resolves, the
  site is body-less under the HTTP-method convention.

When the option is non-literal (a proc, a method call, an instance
variable), the option is ignored and today's "prefer JSON over HTML"
lookup applies (FR-003).

**Rationale**: A developer who writes `formats: :json` is being
explicit about what the action returns; honoring it precisely is the
whole point of the feature. The array form is the next-most-common
explicit form (typical for `respond_to`-derived bones); honoring it
keeps the rule symmetric. Procs and method calls are out of scope —
we cannot resolve them statically.

**Alternatives considered**:
- *Always honor whichever format's view exists first on disk*: silent
  behavior; the developer's explicit intent is what we want to
  document.
- *Treat `formats: :json` strictly — refuse to fall through to
  `.html.*` even when no JSON view exists*: agrees with the spec's
  "JSON view does not exist → status-known body-less". The
  alternative (silently emit the HTML view) would be misleading.

## R3. Where format-hint resolution lives

**Decision**: `ViewLocator#locate_view` gains a keyword argument
`format_hint:` (Symbol, Array<Symbol>, or nil) that controls the
candidate-extension order. The same `.json.jbuilder` / `.html.*`
matchers run; only the order changes. When `format_hint` is nil, the
method behaves exactly as today (JSON-preferred).

**Rationale**: Resolution is already centralized in `ViewLocator`.
Pushing the format hint into a separate "resolver" would split the
candidate-lookup logic; pushing it into `RenderExtractor` would
require `RenderExtractor` to take a dependency on `ViewLocator` (it
doesn't today, and shouldn't).

**Alternatives considered**:
- *A new `TemplateResolver` class*: doubles the surface area for the
  same logic. Rejected.
- *Inline the hint at the `Generator` level*: the Generator already
  delegates to `ViewLocator`; the hint belongs alongside the lookup
  itself.

## R4. Where template-site → final-site conversion lives

**Decision**: The Generator's `collect_extra_sites` pipeline gains a
post-processing pass. For every `RenderSite` carrying a `template_name`,
the Generator:
1. Asks `ViewLocator.locate_view(route, template_name, format_hint:
   site.format_hint)` for the resolved view.
2. If the view is `.json.jbuilder`, parses it via `JbuilderParser` and
   replaces the template site with a JSON site
   (`head: false, schema: <jbuilder schema>`).
3. If the view is `.html.*`, replaces the site with an HTML-template
   site (`head: false, schema: nil, kind_hint: :html_page`).
4. If no view exists, replaces the site with a body-less JSON site
   (`head: false, schema: nil`).

The action's own template render is collected by `RenderExtractor#extract`
into `render_result.render_sites` in the same form; the Generator's
post-processing iterates all sites uniformly (action body + extras).

**Rationale**: Keeps `RenderExtractor` Ripper-only (no I/O), keeps
`ResponseBuilder` agnostic of where a site came from, and threads view
resolution through the one place that already has the route, the
controller, and the view locator: the Generator.

**Alternatives considered**:
- *Have `RenderExtractor` call `ViewLocator` directly*: breaks the
  "extractor parses AST, generator orchestrates" separation.
- *A new field on `RenderResult` listing pre-resolved schemas*: same
  net effect with more coupling. Rejected.

## R5. HTML-template sites in the multi-status model

**Decision**: An HTML-template site carries a small "kind hint"
(`:html_page`) on the `RenderSite`. The Generator's site-list
post-processing then chooses the operation's overall `kind`:
- If ANY site (including a JSON-template site or any `render json:`
  site) is JSON-shaped → kind `:json`. HTML-template sites at the same
  status as a JSON site are dropped (FR-006).
- If every site is HTML-template and there is exactly one status, the
  operation classifies as `:html_page` (today's behavior) — single
  entry, kind `:html_page`.
- Otherwise (a mix of HTML-template at different statuses) → kind
  `:json` (the multi-status response is best modeled as JSON with
  body-less entries; OpenAPI 3.1 does not naturally express "this
  operation returns HTML at 200 and JSON at 401").

**Rationale**: This preserves the existing single-page HTML
documentation for actions that only render an HTML view, while letting
the multi-status model take over when any error / guard renders JSON.
The "drop HTML at same status as JSON" rule mirrors feature 010's
"JSON wins" rule for body collapse (FR-006).

**Alternatives considered**:
- *Emit `text/html` and `application/json` together under the same
  status*: legal in OpenAPI 3.1, but the documented content would not
  match the runtime (the action either renders HTML or JSON, not
  both). Rejected.

## R6. Status assignment for template renders

**Decision**: A template render's status follows the same rule as
`render json:` (feature 010 R1):
- Explicit `status:` option → that status (resolved via
  `STATUS_CODES`).
- No `status:` option → the HTTP-method convention
  (GET/PUT/PATCH→200, POST→201, DELETE→204).

**Rationale**: Identical to feature 010; the user-facing semantics
("the status this render emits at runtime") are identical.

**Alternatives considered**:
- *Treat every template render as 200 regardless of method*: would
  mis-document POST creates that render the show view (Rails returns
  201 for those by default unless the action sets the status
  explicitly — wait, actually Rails returns 200 for `render` even on
  POST; the convention is only applied when no explicit render
  exists). Hmm. **Resolved**: stick with the HTTP-method convention
  per feature 010 R1 — internally consistent and the documented
  behavior matches feature 010's single source of truth.

## R7. Bare action symbol resolution

**Decision**: `render :show` is treated as a template named `"show"`
relative to the route's controller (today's `ViewLocator` rule).
`render :ok` would attempt to resolve a template named `"ok"`; in the
overwhelming majority of cases no such template exists, so the site
contributes a body-less entry under the HTTP-method convention. This
matches today's behavior; the feature does not add bare-status-symbol
detection (FR-009 / Edge Cases / "render :ok").

**Rationale**: Avoids ambiguity. Detecting bare-status-symbol renders
correctly would require a special-case lookup against `STATUS_CODES`,
which competes with the legitimate "render a template named after a
Rails action" idiom. Today's behavior is conservative; we keep it.

## R8. `before_action` template renders

**Decision**: Already-resolved `before_action` callback bodies are
walked by the Generator (feature 010 US3); template renders inside
them are picked up by the same `collect_sites` pass. No additional
machinery is needed.

**Rationale**: The walker is the single source of "reachable bodies".
This feature inherits its semantics, including `only:` / `except:`
filtering (feature 010 R6).

## R9. Determinism

**Decision**: Template-site post-processing is deterministic: the
same `ViewLocator` candidates in the same order, the same
`JbuilderParser` output (already deterministic — feature 002), and
sites within one status collapse via the same canonical-JSON sort
(feature 010 R9). No new sources of nondeterminism.

**Rationale**: Constitution-level requirement (Principle II /
feature 010 FR-013). Nothing in this feature touches ordering.

## R10. Backward compatibility — single-render operations

**Decision**: For an operation whose only render today is a single
action-body template render (e.g. `def show; render "pages/show";
end`), the new pipeline produces exactly one site → one entry under
the HTTP-method convention → the same single-key `responses` map as
today. Verified by re-running the existing HTML-page and jbuilder-view
integration specs.

**Rationale**: SC-004 is a hard requirement; the change must be
purely additive at the per-operation level.

**Alternatives considered**:
- *Run the new pipeline on JSON operations only and leave HTML
  classifications on the old path*: doubles the resolution code. The
  cleaner approach is to push everything through the new pipeline
  and rely on per-operation byte-identity tests.
