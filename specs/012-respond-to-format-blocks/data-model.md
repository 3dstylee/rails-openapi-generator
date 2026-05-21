# Phase 1 Data Model: respond_to Format Blocks

The feature extends `RenderSite` (features 010/011) and `ResponseEntry`
(feature 010) with one optional field each, adds one new internal
constant (format → content-type map), and threads a new branch
through `DocumentBuilder.entry_content`. No existing struct is
removed; no new top-level class is introduced.

## Modified entity: `RenderSite` (lib/rails_openapi_generator/render_extractor.rb)

| Field | Type | Existed? | Description |
|-------|------|----------|-------------|
| `explicit_status` | Integer / nil | yes | Render's `status:` option (or `head` argument); nil otherwise. |
| `schema` | Hash / nil | yes | OpenAPI schema (literal render or resolved jbuilder); nil for body-less / unresolved sites. |
| `head` | Boolean | yes | True for a `head` call. |
| `source` | Symbol | yes | `:action`, `:helper`, `:before_action`. |
| `template_name` | String / nil | yes | Unresolved template name for a template-render site. |
| `format_hint` | Symbol / Array<Symbol> / nil | yes | Literal `formats:` option from a template render. |
| `kind_hint` | Symbol / nil | yes | `:html_page` for a resolved HTML-template site. |
| **`content_type`** | **String / nil** | **NEW** | The OpenAPI content type this site contributes (`"application/json"` for a `format.json` gate, `"text/html"` for a `format.html` gate). Nil for non-format-gate sites — those use the existing per-kind emission path. |

### Validation rules

- `content_type` is non-nil ONLY for sites originating from a
  `respond_to` format gate. JSON-render and head sites and ordinary
  template sites leave it nil.
- A format gate whose block contains an explicit render still carries
  the gate's `content_type`; the inline render's schema is captured
  in `schema` (after template resolution if the inline render is a
  template render).
- A gate for an unmapped format symbol is NOT emitted — no `RenderSite`
  is created for `format.xml` / `format.csv` / etc. (FR-008).

## Modified entity: `ResponseEntry` (lib/rails_openapi_generator/response.rb)

| Field | Type | Existed? | Description |
|-------|------|----------|-------------|
| `status` | Integer | yes | HTTP status code. |
| `body` | Hash / nil | yes | OpenAPI schema for a single-content-type entry. Nil for body-less. |
| **`content_types`** | **Hash<String, Hash | nil> / nil** | **NEW** | When set, supersedes `body` for emission: each key is a content type, each value is the per-content-type schema (or nil for a known-but-schema-less content type like `text/html`). When nil, the existing `body`-based emission applies. |

### Validation rules

- `content_types`, when set, is a non-empty Hash with at least one
  entry. Each key is a String like `"application/json"` or
  `"text/html"`.
- Each value is either a schema Hash (for `application/json`) or
  `nil` (for content types whose schema is the type marker only —
  `text/html`).
- When `content_types` is set, `body` is ignored at emission time.

## New constant: `RenderExtractor::FORMAT_CONTENT_TYPES`

```text
:json => "application/json"
:html => "text/html"
```

The full v1 map. Two entries.

## `respond_to` detection (RenderExtractor)

Inside `extract` and `collect_sites`:

1. Walk the body for `:method_add_block` nodes whose call is
   `respond_to` (an `:fcall` or `:method_add_arg` to `respond_to`).
2. For each, read the block-parameter name from the
   `[:block_var, [:params, [[:@ident, NAME, ...]], ...]]` node. If
   no block param, skip.
3. Walk the block body for `:call` nodes (including those wrapped in
   `:method_add_block` when the format has its own body block) where
   the receiver is `[:var_ref, [:@ident, NAME, ...]]` and NAME
   matches the captured block-param name. The method name on the
   `:call` is the format symbol (e.g. `"html"`, `"json"`).
4. Look up the format symbol in `FORMAT_CONTENT_TYPES`. If unmapped,
   skip the gate.
5. Build the gate's site:
   - If the `format.X` call has its own block AND that block's
     body contains a render call (`render json:`, `render "..."`,
     `head`, etc.) → recursively apply the existing render-detection
     rules to the block; the resulting sites carry the gate's
     `content_type`.
   - Otherwise → emit a single unresolved template-render site with
     `template_name = "<route.controller>/<route.action>"` (default
     view) and `format_hint = format_symbol`, plus
     `content_type = FORMAT_CONTENT_TYPES[format_symbol]`.

Note: the default-view name `"<route.controller>/<route.action>"`
requires the route — which `RenderExtractor` doesn't have today. So
the gate site is emitted with `template_name = nil` and a SPECIAL
marker; the Generator's `resolve_template_sites!` pass plugs in the
route's controller/action when resolving. (Implementation detail —
see the plan; the resolver already has the route.)

## Site lifecycle for a format gate

```text
RenderExtractor parses a respond_to block:
  ↓ For each format.X gate:
    – Map :X to content_type via FORMAT_CONTENT_TYPES. Skip if unmapped.
    – If the gate has an inline render block with a render call → emit
      the inline render's site(s), each tagged with content_type.
    – Else → emit one unresolved gate site:
        explicit_status: nil (or the block's render status, if known)
        schema: nil
        head: false
        source: as-collected (:action / :helper / :before_action)
        template_name: SENTINEL_DEFAULT_VIEW
        format_hint: <format symbol>
        kind_hint: nil
        content_type: FORMAT_CONTENT_TYPES[format_symbol]
  ↓
Generator's resolve_template_sites! pass (feature 011):
  ↓ For each site with template_name == SENTINEL_DEFAULT_VIEW:
    – Replace template_name with "<route.controller>/<route.action>".
    – Continue today's resolution: locate the view with format_hint,
      parse jbuilder for :json, or mark kind_hint :html_page for :html,
      or leave body nil when no view exists.
  ↓
ResponseBuilder groups sites by status as today, then computes the
entry's body OR content_types:
  ↓ If exactly one content_type is present across the group's non-head
    sites → today's path (single body / kind).
  ↓ If two or more distinct content_types are present (e.g. one JSON
    gate + one HTML gate at the same status) → build a content_types
    map: { content_type => union body for that content_type }.
    The union body uses today's per-status rule (identical schemas
    dedup, distinct schemas union into oneOf), but scoped to sites
    whose content_type matches the key.
  ↓
DocumentBuilder.entry_content:
  ↓ If entry.content_types is set → emit each content type's schema
    under one OpenAPI content: map, sorted by content-type string
    ascending.
  ↓ Else → today's per-kind emission applies (byte-identical).
```

## Per-status body computation with content types

| Sites at status X | Resulting entry shape |
|-------------------|----------------------|
| 0 sites | (no entry at status X) |
| 1 head site | `body: nil`, no content_types |
| 1 JSON gate site, default view → schema | `body: <schema>`, no content_types (single-content single-entry — byte-identical to feature 011) |
| 1 HTML gate site, default view exists | `kind: :html_page`, body: nil (single-entry html_page response — byte-identical) |
| 1 JSON gate + 1 HTML gate (both with views) | `content_types: { "application/json" => <jbuilder schema>, "text/html" => nil }`, kind: :json |
| 1 JSON gate (no view) + 1 HTML gate (view exists) | `content_types: { "application/json" => nil, "text/html" => nil }`, kind: :json |
| 1 JSON gate + 1 HTML gate + 1 top-level `render json: { ... }` (all at same status) | `content_types: { "application/json" => <union of jbuilder + literal>, "text/html" => nil }`, kind: :json |
| 1 JSON gate + 1 top-level `render json: { ... }` (no HTML gate, both at same status) | `body: <union>`, no content_types (single content type — falls back to today's emission) |
| 2 JSON gates at different statuses + 0 HTML | Two single-content entries; today's multi-entry JSON shape |

## Emission rule (DocumentBuilder.entry_content)

```text
def entry_content(response, entry)
  return content_map_from(entry.content_types) if entry.content_types

  # ...today's path: switch on response.kind, build content from
  # entry.body for :json, text/html for :html_page, etc.
end

def content_map_from(content_types)
  content_types.sort.to_h.transform_values { |schema|
    schema ? { "schema" => schema } : { "schema" => { "type" => "string" } if html-ish }
  }
end
```

Concrete output for both-format case:

```yaml
'200':
  description: Successful response
  content:
    application/json:
      schema:
        type: object
        properties: ...
    text/html:
      schema:
        type: string
```

(The `text/html` schema is the existing `{type: string}` placeholder
from today's HTML-page emission — features 003 / 011's convention.)

## Single-entry vs. multi-entry (SC-004 preservation)

For any operation that does NOT contain a `respond_to` block:
- No format-gate sites are emitted.
- `content_type` on every site stays nil.
- `content_types` on every entry stays nil.
- `DocumentBuilder.entry_content` takes today's path.
- The OpenAPI output is byte-identical to `0.10.0`.

For an operation whose `respond_to` block contributes only one
content type (only `format.json` or only `format.html`):
- One gate site → one entry → `content_types` stays nil (because no
  sibling at the same status has a different content type) → today's
  emission path → single content type, byte-identical to a regular
  template-render operation.

`content_types` is set ONLY when the multi-content-type case
genuinely applies. This is the SC-004 guarantee.
