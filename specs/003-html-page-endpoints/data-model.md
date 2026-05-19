# Phase 1 Data Model: HTML Page & File Download Endpoints

New and changed in-memory objects. Nothing is persisted. These extend the
feature 001/002 pipeline.

## RenderResult (changed)

The feature 002 `RenderResult` gains signals for the non-JSON kinds.

| Field | Type | Notes |
|-------|------|-------|
| `schema` | Hash / nil | (existing) Literal `render json:` body schema. |
| `renders_json` | Boolean | (existing) A happy-path `render json:` is present. |
| `no_content` | Boolean | (existing) `head :no_content` / `head 204`. |
| `file_download` | Boolean | **new** — a `send_file` / `send_data` call is present. |
| `html_inline` | Boolean | **new** — a `render html:` call is present. |
| `template` | String / nil | **new** — the name of an explicitly rendered template (`render :action` / `render "path"` / `render template:`). |

## ViewMatch (new)

The result of resolving an action to a view file.

| Field | Type | Notes |
|-------|------|-------|
| `kind` | Symbol | `:json` (a `.json.jbuilder` file) or `:html` (a `.html.*` file). |
| `path` | String | Absolute path to the view file. |
| `name` | String | The logical template name (e.g. `api/users/index`). |

**Rules**: Produced by `ViewLocator`; nil when no view resolves. Resolution
checks an explicitly rendered template name first, then the Rails convention
path, preferring `.json.jbuilder` over `.html.*`.

## Classification (new)

The outcome of inspecting one action (Key Entity "Render Classification").

| Field | Type | Notes |
|-------|------|-------|
| `kind` | Symbol | `:json`, `:html_page`, `:file_download`, or `:undeterminable`. |
| `render_result` | RenderResult | Carried through for the JSON body path. |
| `jbuilder_file` | String / nil | The `.json.jbuilder` file, when `kind == :json` via a view. |
| `template_name` | String / nil | The HTML page/template name, when `kind == :html_page`. |

**Rules**: Produced by `RenderClassifier` per the R3 precedence. Exactly one
`kind`. `:undeterminable` is only chosen when no JSON, HTML, or download signal
and no locatable view exists.

## Response (changed)

The feature 002 `Response` gains the classification kind.

| Field | Type | Notes |
|-------|------|-------|
| `status` | Integer | (existing) 200 / 201 / 204. |
| `body` | Hash / nil | (existing) JSON body schema; nil for non-JSON and 204. |
| `description` | String | (existing) e.g. `"Successful response"`. |
| `undeterminable` | Boolean | (existing) JSON body could not be determined. |
| `kind` | Symbol | **new** — `:json`, `:html_page`, or `:file_download`. |
| `page_reference` | String / nil | **new** — the HTML template name, for `:html_page`. |

**Rules**: Built by `ResponseBuilder` from a `Classification`. For `:html_page`
the response content type is `text/html`; for `:file_download`,
`application/octet-stream`; for `:json`, unchanged from feature 002. An
undeterminable action yields `kind: :json, undeterminable: true` and receives no
non-JSON marks (FR-009).

## Endpoint (unchanged shape)

`Endpoint` already carries `response` (feature 002) and `tag` (feature 001). No
new field — the HTML/download tag and vendor extension are derived from
`response.kind` by `DocumentBuilder`; the description note is folded in by
`OperationBuilder` from `response.kind` / `response.page_reference`.

## GenerationReport (changed)

| New field | Type | Notes |
|-----------|------|-------|
| `html_page_count` | Integer | Endpoints classified as HTML pages. |
| `file_download_count` | Integer | Endpoints classified as file downloads. |

Both are surfaced in `#summary` (FR-014).

## OpenApiDocument (changed)

A non-JSON operation's `responses` entry uses a non-JSON content type, the
operation gains a kind tag and a vendor extension, and its `description` carries
a note:

```text
# HTML page operation
"tags": ["Api::PagesController", "HTML Pages"],
"description": "…\n\n_Renders an HTML page (`photopea/edit`)._",
"x-renders-html": true,
"x-html-template": "photopea/edit",
"responses": {
  "200": { "description": "Successful response",
           "content": { "text/html": { "schema": { "type": "string" } } } }
}

# File download operation
"tags": ["Api::FilesController", "File Downloads"],
"description": "…\n\n_Sends a file download._",
"x-sends-file": true,
"responses": {
  "200": { "description": "Successful response",
           "content": { "application/octet-stream":
                        { "schema": { "type": "string", "format": "binary" } } } }
}
```

## Pipeline (entity flow — additions in **bold**)

```text
Route ──> SourceLocator ──> ActionSource
   ├─ RenderExtractor ──> RenderResult  (now incl. file_download, html_inline, template)
   └─ ViewLocator ──────> **ViewMatch** (kind :json | :html)
   **RenderClassifier** (RenderResult + ViewMatch) ──> **Classification**
   ResponseBuilder (Classification) ──> Response (now incl. kind, page_reference)
OperationBuilder ──> Endpoint  (description note folded in)
DocumentBuilder ──> OpenApiDocument  (content type, tags, vendor extension by kind)
Generator ──> GenerationReport (html_page_count, file_download_count)
```
