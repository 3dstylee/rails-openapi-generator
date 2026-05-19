# Contract: Wrapper Resolution Output

How wrapper-resolved downloads appear in the generated document. This feature
adds **no new output shape** — it changes which actions are *classified* as
file downloads.

## A download reached through a wrapper

Before this feature, an action that streams a file via a helper (e.g.
`send_file_and_cleanup`) had no detectable signal → classified `:undeterminable`
→ a bare success response:

```json
"get": {
  "operationId": "get_reports_id",
  "responses": { "200": { "description": "Successful response" } }
}
```

After this feature, the helper is resolved to its definition, the `send_file`
inside is found, and the operation is documented exactly like a **direct**
file-download endpoint (feature 003):

```json
"get": {
  "operationId": "get_reports_id",
  "tags": ["Api::ReportsController", "File Downloads"],
  "description": "_Sends a file download._",
  "x-sends-file": true,
  "responses": {
    "200": {
      "description": "Successful response",
      "content": { "application/octet-stream": { "schema": { "type": "string", "format": "binary" } } }
    }
  }
}
```

There is no marker distinguishing a wrapper-resolved download from a direct one
— they are the same kind of endpoint (FR-012).

## Configuration

`Configuration` gains one setting:

```ruby
RailsOpenapiGenerator.configure do |config|
  config.download_resolution_depth = 5   # default 5; how deep wrapper chains are followed
end
```

`download_resolution_depth` must be an integer `>= 1`; an invalid value raises
`ConfigurationError` before generation begins.

## Run report

A wrapper-resolved download is counted in the existing file-download count — the
report gains no new line:

```text
  File downloads: 8 endpoints
```

## Guarantees

- Only actions that were previously **undeterminable** can change; JSON, HTML,
  and direct-download classifications are byte-for-byte unchanged (FR-010).
- No controller action or helper method is executed (FR-009).
- Resolution terminates: bounded by `download_resolution_depth`, cycle-guarded,
  and ends any branch whose method cannot be located (FR-005–FR-007).
- Output is deterministic and still validates against the OpenAPI 3.1 schema
  (FR-011).
