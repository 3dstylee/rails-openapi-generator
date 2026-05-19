# Quickstart: HTML Page & File Download Endpoints

What changes for a developer once this feature ships. There is **nothing new to
install or configure** — the marks appear automatically on the next run.

## 1. Generate as before

```sh
rake openapi:generate
```

## 2. What's new in the output

Endpoints that don't return JSON are now classified and marked.

### An HTML-page endpoint

An action that renders a page — explicitly (`render template: "photopea/edit"`)
or implicitly (no `render`, only a `.html.erb` view) — now produces:

```json
"tags": ["Media::ScreenshotsController", "HTML Pages"],
"description": "…\n\n_Renders an HTML page (`photopea/edit`)._",
"x-renders-html": true,
"x-html-template": "photopea/edit",
"responses": {
  "200": { "content": { "text/html": { "schema": { "type": "string" } } } }
}
```

### A file-download endpoint

An action that calls `send_file` / `send_data`:

```json
"tags": ["ExportsController", "File Downloads"],
"description": "_Sends a file download._",
"x-sends-file": true,
"responses": {
  "200": { "content": { "application/octet-stream":
                        { "schema": { "type": "string", "format": "binary" } } } }
}
```

## 3. In the docs viewer

Redoc / Swagger UI now show two extra sidebar sections — **HTML Pages** and
**File Downloads** — so page and download routes are visually separated from
the JSON API. Each operation also reads, in its description, that it renders a
page or sends a file.

## 4. Run report

```text
OpenAPI document written to doc/openapi.json
  Processed:      626 endpoints
  HTML pages:     128 endpoints
  File downloads: 6 endpoints
  Skipped:        1
  Warnings:       22
```

## 5. JSON endpoints are untouched

Endpoints that render JSON (jbuilder view or literal `render json:`) are
byte-for-byte unchanged — same response schemas, same tags, same descriptions.
A `render json:` always wins, so a JSON action that also happens to have an
HTML view is still documented as JSON.

## 6. Filtering, if you want only the JSON API

The `x-renders-html` / `x-sends-file` flags make non-JSON endpoints easy to
strip in a post-processing step, and the `route_filter` config still works to
exclude them before generation.

## Acceptance smoke test

| Spec story | Quickstart step proving it |
|------------|----------------------------|
| US1 — non-JSON endpoints distinguished | Step 2/3 — HTML & download endpoints marked and grouped |
| US2 — machine-readable flag | Step 2 — `x-renders-html` / `x-sends-file` present |
| US3 — report counts | Step 4 — HTML page / file download counts |
