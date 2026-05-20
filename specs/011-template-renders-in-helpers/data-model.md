# Phase 1 Data Model: Template Renders in Helpers

The feature extends `RenderSite` (feature 010), tweaks `ViewLocator`'s
signature, and adds one Generator helper. No existing struct is
removed; no new top-level class is introduced.

## Modified entity: `RenderSite` (lib/rails_openapi_generator/render_extractor.rb)

The render-call descriptor gains two optional fields. The existing
`status` / `schema` / `head` / `source` semantics are unchanged.

| Field | Type | Existed? | Description |
|-------|------|----------|-------------|
| `explicit_status` | Integer / nil | yes | Render's `status:` option (or `head` argument); nil for status-less template / json render. |
| `schema` | Hash / nil | yes | OpenAPI schema for a literal `render json:` value; populated only by the Generator's post-processing pass when the site is a template that resolved to a `.json.jbuilder`. |
| `head` | Boolean | yes | True for a `head` call. |
| `source` | Symbol | yes | `:action`, `:helper`, `:before_action`. |
| **`template_name`** | **String / nil** | **NEW** | The template name for a template-render site (e.g. `"api/v2/workflow/home_staging_orders/show"`). Nil for `render json:`, `head`, and post-processed sites. |
| **`format_hint`** | **Symbol, Array<Symbol>, or nil** | **NEW** | The render's literal `formats:` option, when present. Nil when the option is absent or non-literal. |
| **`kind_hint`** | **Symbol / nil** | **NEW** | `:html_page` for an HTML-template site after Generator post-processing; nil otherwise (JSON sites and not-yet-resolved template sites). |

### Validation rules

- `template_name` is non-nil only for sites originating from a
  template render. `head: true` sites and JSON-render sites always
  have `template_name: nil`.
- `format_hint`, when set, is either a Symbol or a non-empty
  Array<Symbol>. Anything else is treated as "no hint" and the field
  is nil.
- A site with `template_name` set is "unresolved" until the
  Generator's post-processing step converts it to a JSON site (with
  schema or body-less) or to an HTML-template site (with
  `kind_hint: :html_page`).

## Modified entity: `ViewLocator#locate_view` (lib/rails_openapi_generator/view_locator.rb)

The signature gains one keyword argument.

```text
locate_view(route, template_name = nil, format_hint: nil) → ViewMatch | nil
```

| Parameter | Type | Behavior |
|-----------|------|----------|
| `route` | Route | unchanged. |
| `template_name` | String / nil | unchanged. |
| `format_hint` | Symbol, Array<Symbol>, or nil | NEW. When `:json` → only `.json.jbuilder` candidates are tried. When `:html` → only `.html.*` candidates are tried. When `[:json, :html]` (or any array) → try each in order. When nil → today's "JSON-preferred" lookup applies. |

Return value (`ViewMatch`) is unchanged.

## Site lifecycle (template → resolved)

```text
RenderExtractor parses an action / helper / before_action body
  ↓ Detect every `render` call.
  ↓ If the call has `:json` → site with schema (today's path).
  ↓ If the call has `:html` → ignored (inline HTML, handled elsewhere).
  ↓ If the call is `head` → site with head: true.
  ↓ Otherwise, if a template name is recoverable
    (positional String / Symbol, or `template:`, or `action:`)
    → unresolved site with `template_name` and `format_hint`.
  ↓
Generator collects all sites (action body + extras).
  ↓ For each unresolved site (template_name != nil):
    – ask `ViewLocator.locate_view(route, template_name, format_hint:)`
    – if .json.jbuilder → parse via JbuilderParser, replace with a
      resolved JSON site (`schema: <parsed>`, template_name: nil).
    – if .html.*       → replace with a resolved HTML-template site
      (`kind_hint: :html_page`, `template_name: nil`).
    – if no view       → replace with a body-less JSON site
      (`schema: nil`, `template_name: nil`).
  ↓
ResponseBuilder receives a uniform site list — every site has
status + schema (nullable) + head + optional kind_hint, with no
template_name remaining.
  ↓ Group by status, apply union/dedup, choose overall kind:
    – any JSON site → kind :json
    – every site is HTML-template and exactly one status → :html_page
    – otherwise (mixed HTML at one status + JSON at another) → :json
```

## Construction flow (input → output)

| Source | Step | Output |
|--------|------|--------|
| Controller AST | `RenderExtractor.extract` | `RenderResult.render_sites: [RenderSite]` — JSON / head / unresolved-template sites |
| `RenderResult` + helper / before_action bodies | Generator's `collect_extra_sites` | Combined site list, post-processed to resolved sites |
| Resolved site list | `ResponseBuilder.build` | `Response` with `entries` per feature 010 rules + chosen kind |
| `Response` | `DocumentBuilder#responses` | OpenAPI `responses` map |

## Status assignment

A template render's status follows the same rule as feature 010 R1:
- Explicit `status:` option → that status code.
- Otherwise → HTTP-method convention (GET/PUT/PATCH → 200, POST → 201, DELETE → 204).

## Union and dedup rules (FR-005 / FR-006)

At each status, the existing feature-010 rules apply, with one
addition: an HTML-template site collapses out when **any** JSON site
exists at the same status (FR-006).

| Sites at status X | Resulting Entry body | Operation kind tip |
|-------------------|----------------------|--------------------|
| 0 sites | (no entry — status X does not appear) | — |
| 1 head site | `nil` | — |
| 1 JSON site with schema `S` | `S` | JSON |
| 1 JSON site, no schema | `nil` | JSON |
| 1 HTML-template site | `nil` (no `content` key emitted at JSON kind) | HTML if every other site is also HTML-template at the same status; else JSON |
| 1 head + 1 JSON w/ schema `S` | `S` | JSON |
| N identical-schema JSON sites | `S` | JSON |
| N distinct-schema JSON sites | `{"oneOf": [S_sorted]}` | JSON |
| 1 JSON + 1 HTML-template (same status) | JSON site's body | JSON (HTML-template drops at same status as JSON; FR-006) |
| All HTML-template, exactly one status total | `nil`, kind `:html_page` (today's HTML-page single-response shape) | HTML |
| HTML-template at status X + JSON at status Y | per-status union; overall kind JSON | JSON |

## Single-entry vs. multi-entry (SC-004 preservation)

For an operation whose only render in 0.9.0 was a single action-body
template render — i.e. an HTML page (`render "pages/show"`) or a
jbuilder-view JSON action (`def index; end` with a
`.json.jbuilder` view) — the new pipeline produces exactly one site →
one entry → byte-identical OpenAPI output. Verified by the existing
HTML-page and jbuilder-view integration specs (`html_page_endpoints_spec.rb`,
`response_bodies_spec.rb`, `feature_001_regression_spec.rb`).
