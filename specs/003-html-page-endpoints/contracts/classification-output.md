# Contract: Classification Output

How HTML-page and file-download endpoints appear in the generated document
after this feature. This refines feature 001/002 contracts; the library API,
rake task, and CLI signatures are unchanged.

## JSON endpoint (unchanged)

An endpoint classified as JSON is byte-for-byte unchanged from feature 002 —
`responses` with an `application/json` schema (or a body-less response when
undeterminable), no kind tag, no vendor extension, no page note.

## HTML page endpoint

```json
"get": {
  "operationId": "get_screenshots_id_edit_image",
  "tags": ["Media::ScreenshotsController", "HTML Pages"],
  "summary": "Edit a screenshot",
  "description": "Opens the editor.\n\n_Renders an HTML page (`photopea/edit`)._\n\n_Source: `app/controllers/media/screenshots_controller.rb:87`_",
  "x-renders-html": true,
  "x-html-template": "photopea/edit",
  "parameters": [ { "name": "id", "in": "path", "required": true, "schema": { "type": "string" } } ],
  "responses": {
    "200": {
      "description": "Successful response",
      "content": { "text/html": { "schema": { "type": "string" } } }
    }
  }
}
```

- `text/html` response content type, no JSON body schema.
- `_Renders an HTML page (`<template>`)._` appended to the description; the
  `(`<template>`)` part is omitted when the template name is not known
  (e.g. `render html:` inline).
- `"HTML Pages"` added to `tags`, alongside the controller tag.
- `x-renders-html: true`, plus `x-html-template` when the template is known.

## File download endpoint

```json
"get": {
  "operationId": "get_exports_id_download",
  "tags": ["ExportsController", "File Downloads"],
  "description": "_Sends a file download._\n\n_Source: `app/controllers/exports_controller.rb:42`_",
  "x-sends-file": true,
  "responses": {
    "200": {
      "description": "Successful response",
      "content": { "application/octet-stream": { "schema": { "type": "string", "format": "binary" } } }
    }
  }
}
```

- `application/octet-stream` response content type, `format: binary` schema.
- `_Sends a file download._` appended to the description.
- `"File Downloads"` added to `tags`, alongside the controller tag.
- `x-sends-file: true`.

## Undeterminable endpoint (unchanged)

An action with no JSON render, no HTML/download signal, and no locatable view
keeps feature 002 behavior: a body-less success response, no kind tag, no
extension, no note. It is reported as "response shape could not be determined".

## Top-level tags

The document's top-level `tags` array gains `{ "name": "HTML Pages" }` and/or
`{ "name": "File Downloads" }` when any endpoint of that kind exists, sorted
alongside the controller tags.

## Run report

The report summary gains two lines:

```text
  HTML pages:     128 endpoints
  File downloads: 6 endpoints
```

## Guarantees

- The document continues to validate against the OpenAPI 3.1 schema (FR-012).
- Output is deterministic for unchanged input (FR-012).
- No controller action is executed (FR-011).
- JSON endpoints are byte-for-byte unchanged from feature 002 output (FR-013).
- A `render json:` always wins — a JSON endpoint is never marked HTML/download
  even if an HTML view also exists (FR-004).
