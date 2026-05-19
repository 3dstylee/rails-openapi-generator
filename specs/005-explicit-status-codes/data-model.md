# Phase 1 Data Model: Explicit Success Status Codes

This feature changes one existing value object and the status logic of one
builder. No new entities.

## RenderResult (changed)

| Field | Type | Notes |
|-------|------|-------|
| `schema` | Hash / nil | (existing) Literal `render json:` body schema. |
| `renders_json` | Boolean | (existing) A happy-path `render json:` is present. |
| `file_download` | Boolean | (existing) A `send_file`/`send_data` call is present. |
| `html_inline` | Boolean | (existing) A `render html:` call is present. |
| `template` | String / nil | (existing) Explicitly rendered template name. |
| `explicit_status` | Integer / nil | **new** — the last happy-path (2xx/3xx) status code set by a `head` call or a `render … status:` option; nil when none. |
| `head` | Boolean | **new** — true when the action has a happy-path `head` call (its response is body-less). |

**Removed**: `no_content` — subsumed by `explicit_status` (`head :no_content` →
`explicit_status: 204`) and `head`.

**Rules**:
- A status signal is a `head` argument or a `render`'s `status:` value.
- Each signal is resolved to a numeric code (symbol via the status table, or an
  integer directly); only codes in 200–399 are kept; the last is `explicit_status`.
- An unmappable symbol contributes no signal.

## Response (unchanged shape)

No structural change. `ResponseBuilder` populates `Response#status` and
`Response#body` differently:

| Aspect | Before | After |
|--------|--------|-------|
| `status` | HTTP-method convention only | `RenderResult.explicit_status` when present, else the HTTP-method convention |
| `body` | per kind; nil for 204 | per kind; nil for 204 **and** when `RenderResult.head` is true |

`kind`, `page_reference`, `description`, and `undeterminable` are unchanged.

## Status resolution flow

```text
RenderExtractor (one AST scan of the action):
  render calls   ── status: option ──┐
  head  calls    ── argument ────────┤── resolve to codes (status table / integer)
                                     └── keep 2xx/3xx ── last ── RenderResult.explicit_status
  any happy head call ───────────────────────────────────────── RenderResult.head

ResponseBuilder.build(route, classification, view_schema):
  status = render_result.explicit_status || method_convention(route)
  body   = nil if status == 204 || render_result.head
         else (per kind, as today)
```
