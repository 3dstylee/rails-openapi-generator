# Quickstart: respond_to Format Blocks

A short end-to-end check that `respond_to do |format| ... end`
detection works once implemented. Run from the gem's repository root.

## 1. Confirm the dummy fixture exercises every scenario

`spec/fixtures/dummy/app/controllers/api/respond_to_controller.rb`
should expose:

- A `GET` action that does `respond_to { |format| format.html { ... };
  format.json }`, with both `.html.erb` and `.json.jbuilder` views —
  the motivating case (200 with both content types).
- A `GET` action that does `respond_to { |format| format.json }` with
  only a `.json.jbuilder` view — single-content-type case.
- A `GET` action that does `respond_to { |format| format.html }` with
  only a `.html.erb` view — single-content-type HTML-page case
  (byte-identical to today's HTML-page).
- A `GET` action that does `respond_to { |format|
  format.json { render json: { id: 1, ok: true } }; format.html }` —
  explicit-render-inside-block (200 with literal JSON schema +
  default `.html.erb` schema).
- A `GET` action that does `respond_to { |format| format.xml }` (an
  unmapped format) — operation is documented as if `respond_to` were
  absent.

Views under `spec/fixtures/dummy/app/views/api/respond_to/`:
- `index.json.jbuilder` and `index.html.erb` for the both-formats case
- `json_only.json.jbuilder` (no .html.erb)
- `html_only.html.erb` (no .json.jbuilder)
- one with an explicit-render block, no view needed for the JSON path

## 2. Generate the document against the dummy app

```bash
bundle exec rspec spec/integration/respond_to_format_blocks_spec.rb
```

The integration spec asserts, per fixture action:

1. The `responses` keys are exactly those expected.
2. The both-formats action's `200` entry has `content` with BOTH
   `application/json` (jbuilder schema) and `text/html` (placeholder
   schema), sorted by content-type name ascending.
3. The single-JSON action's `200` entry has only `application/json`.
4. The single-HTML action's `200` entry has only `text/html`, kind
   `:html_page` — byte-identical to a feature-011 HTML-page operation.
5. The explicit-render-inside-block action's `application/json` schema
   matches the literal `render json:` shape (not the default view).
6. The unmapped `format.xml` action is documented as if no
   `respond_to` were present (today's fallback rules apply).
7. `GenerationReport.warnings` contains no
   "response shape could not be determined" entries for any of the
   above with at least one mapped, resolved gate.

## 3. Regression check — operations without `respond_to` unchanged

```bash
bundle exec rspec spec/integration/feature_001_regression_spec.rb \
                  spec/integration/html_page_endpoints_spec.rb \
                  spec/integration/response_bodies_spec.rb \
                  spec/integration/multi_status_responses_spec.rb \
                  spec/integration/template_renders_in_helpers_spec.rb
```

The existing integration specs must continue to pass byte-identically
— operations that do not use `respond_to` produce the same response
maps as in `0.10.0` (SC-004).

## 4. Validate against OpenAPI 3.1 schema

```bash
bundle exec rspec spec/integration/generate_all_endpoints_spec.rb
```

The fixture document — now containing the new
`api/respond_to/*` operations with multi-content-type entries — must
pass schema validation.

## 5. Determinism check

```bash
bundle exec rspec spec/integration/determinism_spec.rb
```

The both-formats operation's `content` map (with two content types)
must be byte-identical across two consecutive runs, including the
content-type ordering.

## 6. Manual smoke check against a real app (optional)

```bash
cd path/to/some-rails-app
bundle exec rails-openapi-generator generate --out /tmp/openapi.yaml
```

Find an action that uses `respond_to do |format|; format.html { ... };
format.json; end`. Its `responses` map should now show a single
status entry whose `content:` carries both `application/json` (with
the jbuilder schema if one exists) and `text/html` (with the
placeholder schema). Before this feature, the operation likely had
no content at all.
