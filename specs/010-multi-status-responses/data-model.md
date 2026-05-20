# Phase 1 Data Model: Multi-Status Responses

The feature reshapes `Response`, extends `RenderResult`, and adds one new
type. No existing kind enum is changed; the precedence between `:json` /
`:redirect` / `:file_download` / `:html_page` / `:undeterminable` is
preserved.

## New entity: `RenderSite` (lib/rails_openapi_generator/render_extractor.rb)

A single `render json:` or `head` call, located somewhere in the
reachable code (action body, helper method, or `before_action`
callback).

| Field | Type | Description |
|-------|------|-------------|
| `status` | Integer | The HTTP status the call would emit at runtime. For a `render json:` without a `status:` option, this is the HTTP-method convention status for the route. For a `render json:` with a known `status:` symbol or integer, it is that status. For a `head` call, it is the head's argument (or 200 when no argument). |
| `schema` | Hash / nil | The OpenAPI schema derived from a literal `render json: <hash/array>` value, or nil when the call is a `head` or when the `json:` value is non-literal. |
| `head` | Boolean | True when this site is a `head` call; false when it is a `render json:`. |
| `source` | Symbol | One of `:action`, `:helper`, `:before_action`. Carried for diagnostic / test-asserting purposes; not emitted to the OpenAPI document. |

Validation rules:
- `status` must be an integer the system can resolve (Rails status table
  or literal integer). A render whose `status:` symbol is unknown
  contributes no `RenderSite` (research R7).
- `schema`, when present, is the same Hash shape produced by
  `LiteralEvaluator.schema_for` today.
- `head: true` implies `schema: nil`.

## Modified entity: `RenderResult` (lib/rails_openapi_generator/render_extractor.rb)

The single-action signal struct gains one field. Existing fields are
preserved so the redirect / file-download / html / wrapper paths
continue to work unchanged.

| Field | Type | Existed? | Description |
|-------|------|----------|-------------|
| `schema` | Hash / nil | yes | Happy-path `render json:` literal schema (unchanged). |
| `renders_json` | Boolean | yes | True when ANY `render json:` is present anywhere reachable (broadened from "happy-path render json:"). |
| `explicit_status` | Integer / nil | yes | Last happy-path explicit status (unchanged; kept for non-JSON kinds that still use it). |
| `head` | Boolean | yes | True when the success path is a `head` call (unchanged). |
| `file_download` | Boolean | yes | unchanged. |
| `html_inline` | Boolean | yes | unchanged. |
| `template` | String / nil | yes | unchanged. |
| `redirect_status` | Integer / nil | yes | unchanged (feature 009). |
| **`render_sites`** | **Array<RenderSite>** | **NEW** | **Every render and head call reachable from the action — across the action body, helper methods, and (optionally) before_action callbacks. Empty when no render is reachable.** |

### Validation rules (on `render_sites`)

- Sites are collected in source-deterministic order during extraction;
  the final assembly in `ResponseBuilder` is sort-stable regardless.
- Sites whose status cannot be resolved (R7) are dropped at extraction
  time and never appear in the list.
- A site with `head: true` always has `schema: nil`.

## New entity: `BeforeActionCallback` (lib/rails_openapi_generator/before_action_resolver.rb)

The resolved metadata for one `before_action` declaration applicable to
some set of actions on a controller class.

| Field | Type | Description |
|-------|------|-------------|
| `method_name` | String | The name of the callback method (e.g. `"authenticate"`). |
| `method_node` | AST node | The method's Ripper AST, resolved via `MethodResolver`. `nil` when unresolvable — the callback is then silently skipped. |
| `only` | Set<String> / nil | The action names the callback applies to, when recovered from a literal `only:` array on the controller's own source. `nil` means "no `only:` restriction known — applies to all actions in the controller". |
| `except` | Set<String> / nil | Same idea as `only`, for `except:`. `nil` means "no `except:` restriction known". |

Validation rules:
- When `only` is non-nil, the callback contributes its renders ONLY to
  actions in that set.
- When `except` is non-nil, the callback contributes its renders to
  every action NOT in that set.
- Both `only` and `except` non-nil is permitted (`only` is filtered
  first, then `except` is removed); this matches Rails semantics.
- A callback inherited from a parent or concern, with no own-source
  `only:` / `except:` to recover, has both fields `nil` — applies to
  every action in the controller (research R6, FR-008).

## Modified entity: `Response` (lib/rails_openapi_generator/response.rb)

The big reshape. `Response` becomes a holder for an ordered list of
entries.

### New nested struct: `Response::Entry`

| Field | Type | Description |
|-------|------|-------------|
| `status` | Integer | The HTTP status of this response entry. |
| `body` | Hash / nil | The OpenAPI schema for this entry's body, or nil for a body-less entry (head, no-known-body, or non-JSON kind). May be an `{"oneOf": [...]}` schema for a multi-shape union. |

### Reshaped `Response`

| Field | Type | Existed? | Description |
|-------|------|----------|-------------|
| **`entries`** | **Array<Entry>** | **NEW** | Ordered (ascending status) list of response entries. Always non-empty; the fallback path produces a list of one undeterminable entry. |
| `description` | String | yes | Unchanged — applied to every entry's "description" field on emission (research R9). |
| `undeterminable` | Boolean | yes | Unchanged — true only in the fallback path (no render reachable, not redirect/file/html). |
| `kind` | Symbol | yes | `:json` / `:html_page` / `:file_download` / `:redirect` (unchanged). |
| `page_reference` | String / nil | yes | Unchanged (html_page template name). |
| ~~`status`~~ | — | **removed** | Read `entries.first.status` (or, where the single entry is the intended one, `entries.last.status` — they are the same in single-entry cases). |
| ~~`body`~~ | — | **removed** | Read `entries.first.body`. |

Helper predicates (`undeterminable?`, `html_page?`, `file_download?`,
`redirect?`) are preserved unchanged.

### Validation rules

- `entries` is sorted by ascending integer status before emission
  (research R9).
- For `:redirect` / `:file_download` / `:html_page` / undeterminable
  fallback paths, `entries.size == 1`.
- For `:json` kind, `entries.size >= 1`. Each entry's `body` is either
  a schema Hash or nil (no nested arrays).

## Construction flow (input → output)

| Source | Step | Output |
|--------|------|--------|
| Controller action AST | `RenderExtractor.extract` (now walking action + helpers + before_action bodies) | `RenderResult` with `render_sites` |
| Controller class | `BeforeActionResolver.resolve(controller_class, action_name)` | List of `BeforeActionCallback` objects, only/except-filtered for `action_name` |
| `RenderResult` + classification | `ResponseBuilder.build` | `Response` with `entries: [Entry(status, body)]` sorted by status |
| `Response` | `DocumentBuilder#responses` | `{"200": {...}, "422": {...}}` OpenAPI map |

## Union and dedup rules (FR-004, FR-005)

When `ResponseBuilder` groups `render_sites` by status:

| Sites at status X | Resulting Entry body |
|-------------------|----------------------|
| 0 sites | (no entry — status X does not appear in the response set) |
| 1 head site | `nil` |
| 1 render site with schema `S` | `S` |
| 1 render site with no schema (non-literal) | `nil` |
| 1 head + 1 render w/ schema `S` | `S` (render wins, FR-005) |
| 2 head sites | `nil` (collapse to one entry) |
| N render sites with no schemas | `nil` |
| N render sites with identical schema `S` | `S` (dedup by Hash equality) |
| N render sites with distinct schemas `S₁..Sₖ` (k ≥ 2) | `{"oneOf": [S_sorted]}` where the list is unique schemas sorted by `JSON.generate(schema)` ascending |
| Mix of head + multi-shape renders | `{"oneOf": [...]}` of unique render schemas; head's no-body contribution dropped (FR-005) |

## Single-entry vs. multi-entry (SC-005 preservation)

An action that today produces one `Response(status: X, body: B, kind:
:json)` corresponds to a new `Response(entries: [Entry(status: X,
body: B)], kind: :json)`. The emitted OpenAPI is byte-identical because
`DocumentBuilder` iterates a one-element list and produces a one-key
`responses` map — the same map the existing code produces.

Likewise for `:redirect`, `:html_page`, `:file_download`, and the
undeterminable fallback: each remains a single-entry `Response` and
emits identically (verified by `feature_001_regression_spec.rb` and the
existing kind-specific specs).
