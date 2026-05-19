# Quickstart: Wrapper Method Resolution for File Downloads

What changes for a developer once this feature ships. There is **nothing new to
do** — wrapper-based downloads are detected automatically on the next run.

## 1. The problem it solves

An action that streams a file through a helper method was previously documented
as a bare `200` — the generator only recognized a literal `send_file`:

```ruby
def show
  output_file = build_export(params[:id])
  send_file_and_cleanup(output_file, filename: File.basename(output_file))
end

private

def send_file_and_cleanup(path, **opts)
  send_file(path, **opts)
ensure
  File.delete(path)
end
```

## 2. What's new

The generator now follows `send_file_and_cleanup` to its definition, finds the
`send_file` inside, and classifies `show` as a **file-download endpoint** — same
result as if the action called `send_file` directly:

```json
"tags": ["Api::ReportsController", "File Downloads"],
"description": "_Sends a file download._",
"x-sends-file": true,
"responses": {
  "200": { "content": { "application/octet-stream":
                        { "schema": { "type": "string", "format": "binary" } } } }
}
```

It works through:

- a helper in the **same controller**,
- a helper in an **included concern/module**,
- a helper in a **parent controller**,
- and **chains** of helpers (a wrapper calling another wrapper).

## 3. Configuration (optional)

Wrapper chains are followed up to 5 levels deep by default. To change it:

```ruby
RailsOpenapiGenerator.configure do |config|
  config.download_resolution_depth = 8
end
```

## 4. What it does NOT do

- It does not follow calls made on another object (`some_service.stream_file`) —
  only the controller's own methods can reach the controller's `send_file`.
- It does not resolve `render` / `render json:` through wrappers — that is a
  separate concern.
- It never executes code; an action whose helper can't be located statically
  stays undeterminable, exactly as before.

## Acceptance smoke test

| Spec story | Quickstart step proving it |
|------------|----------------------------|
| US1 — download via a single wrapper | Step 2 — `send_file_and_cleanup` resolves to a download |
| US2 — download via a wrapper chain | Step 2 — chained helpers are followed |
| US3 — bounded & safe | Step 3 — depth cap; cycles and dead-ends end quietly |
