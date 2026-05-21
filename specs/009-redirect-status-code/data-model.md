# Phase 1 Data Model: Redirect Response Status Code

The feature touches three existing structs and one existing kind enum. No new
struct is introduced.

## Modified entity: `RenderResult` (lib/rails_openapi_generator/render_extractor.rb)

The action-body signal struct gains one field.

| Field | Type | Existed? | Description |
|-------|------|----------|-------------|
| `schema` | Hash / nil | yes | Schema for `render json:` literal. |
| `renders_json` | Boolean | yes | True when a happy-path `render json:` is present. |
| `explicit_status` | Integer / nil | yes | Last happy-path explicit status (`head` / `render status:`). |
| `head` | Boolean | yes | True when the success path is a `head` call. |
| `file_download` | Boolean | yes | True when `send_file` / `send_data` is present. |
| `html_inline` | Boolean | yes | True when `render html:` is present. |
| `template` | String / nil | yes | Last explicit `render :action` / `render "path"`. |
| **`redirect_status`** | **Integer / nil** | **NEW** | **Last happy-path 3xx status from a `redirect_to` / `redirect_back` / `redirect_back_or_to` call. Default `302` when the call has no `status:` option. `nil` when no redirect call is present, or when the only redirect calls carry a non-3xx `status:`.** |

### Validation rules (on `redirect_status`)

- Must be `nil` or an integer in `300..399`.
- When more than one redirect call resolves to a happy-path status, the last in
  source order is the recorded value.
- A `status:` option that resolves to a code outside `300..399` does not
  contribute to `redirect_status` (the redirect call is ignored).
- A `status:` option whose symbol is not in `STATUS_CODES` is treated as "no
  explicit status" — the default `302` applies.

## Modified entity: `Classification.kind` enum (lib/rails_openapi_generator/render_classifier.rb)

The enum gains one variant.

| Variant | Existed? | Meaning |
|---------|----------|---------|
| `:json` | yes | JSON response (literal `render json:` or jbuilder view). |
| `:html_page` | yes | HTML page (inline `render html:` or HTML view). |
| `:file_download` | yes | `send_file` / `send_data` or wrapper-resolved download. |
| `:undeterminable` | yes | Final fallback — response shape unknown. |
| **`:redirect`** | **NEW** | **A `redirect_to` / `redirect_back` / `redirect_back_or_to` redirect. The status code is carried by `render_result.redirect_status`.** |

### Classification precedence (after this change)

```text
:json            (renders_json)
:file_download   (file_download)
:html_page       (html_inline)
:json or :html_page  (view lookup)
:redirect        (redirect_status present)        ← NEW
:file_download   (wrapper resolver)
:undeterminable  (final fallback)
```

## Modified entity: `Response` (lib/rails_openapi_generator/response.rb)

No struct field changes. The struct already carries `status`, `body`,
`description`, `undeterminable`, `kind`, and `page_reference`. A redirect
response is constructed as:

- `status`: the `redirect_status` from the `RenderResult` (a 3xx integer).
- `body`: `nil` (a redirect has no body).
- `description`: `"Successful response"` (the default; per R7 the description
  note is added by `OperationBuilder#page_note`, not by `Response`).
- `undeterminable`: `false`.
- `kind`: `:redirect`.
- `page_reference`: `nil`.

The `kind` enum on `Response` parallels the one on `Classification`; it
already accepts `:json`, `:html_page`, and `:file_download`, and now also
`:redirect`. The two `kind?` helpers (`html_page?`, `file_download?`) gain a
sibling `redirect?` predicate for symmetry.

## Status code derivation (input → output)

| Source in action body | `redirect_status` | Documented status |
|-----------------------|-------------------|-------------------|
| `redirect_to path` | `302` | `302` |
| `redirect_to path, status: :found` | `302` | `302` |
| `redirect_to path, status: 302` | `302` | `302` |
| `redirect_to path, status: :see_other` | `303` | `303` |
| `redirect_to path, status: 303` | `303` | `303` |
| `redirect_to path, status: :moved_permanently` | `301` | `301` |
| `redirect_to path, status: 301` | `301` | `301` |
| `redirect_to path, status: :permanent_redirect` | `308` | `308` |
| `redirect_to path, status: :unprocessable_entity` | `nil` | (existing rule — usually `:undeterminable`) |
| `redirect_to path, status: :totally_made_up` | `302` | `302` (unknown symbol → default) |
| `redirect_back_or_to fallback_path` | `302` | `302` |
| `redirect_back fallback_location: path` | `302` | `302` |
| `head :ok` then later `redirect_to path` | `redirect_status = 302`, `explicit_status = 200` | `302` (kind `:redirect` wins; explicit_status not used here because the action is classified as a redirect, not via `head`). |
| `render json: data` then later `redirect_to path` | `redirect_status = 302`, but kind is `:json` | `201`/`200`/etc. via existing rules (JSON wins per precedence). |

## Document emission (`DocumentBuilder.response_content`)

| `Response.kind` | Emitted `content` | Existed? |
|-----------------|-------------------|----------|
| `:json` (with body) | `application/json` | yes |
| `:json` (no body / undeterminable) | none | yes |
| `:html_page` | `text/html` | yes |
| `:file_download` | `application/octet-stream` | yes |
| **`:redirect`** | **none** | **NEW** |

The redirect response object is therefore `{ "description": "Successful
response" }` filed under the redirect's status code — analogous to a `204`
no-content entry.
