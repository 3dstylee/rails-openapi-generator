# Quickstart: Template Renders in Helpers

A short end-to-end check that template-render-in-helper detection works
once implemented. Run from the gem's repository root.

## 1. Confirm the dummy fixture exercises every scenario

`spec/fixtures/dummy/app/controllers/api/template_renders_controller.rb`
should expose:

- A `PUT` action whose body does a guard `render json: …,
  status: :conflict` and then calls a private helper that does
  `render "api/template_renders/show", formats: :json, handlers:
  [:jbuilder]` (the motivating case — happy 200 with jbuilder schema +
  409 from the JSON render).
- A `GET` action that calls a private helper doing
  `render "api/template_renders/show", formats: :html` (US2 — HTML-
  page classification preserved when no JSON renders contribute).
- A `GET` action that calls a private helper doing
  `render "api/template_renders/missing"` (no view of either format
  exists) — body-less entry under the HTTP-method convention.
- A `DELETE` action whose `before_action` callback does
  `render "api/template_renders/forbidden", status: :forbidden,
  formats: :json` (US3 — template render in callback contributes 403
  entry).

Views in `spec/fixtures/dummy/app/views/api/template_renders/`:
- `show.json.jbuilder` — a small typed jbuilder.
- `show.html.erb` — an HTML alternative for US2.
- `forbidden.json.jbuilder` — for US3.

## 2. Generate the document against the dummy app

```bash
bundle exec rspec spec/integration/template_renders_in_helpers_spec.rb
```

The integration spec asserts, per fixture action:

1. The `responses` keys are exactly those expected (e.g. 200 + 409 for
   the motivating case; 200 alone for the US2 HTML case; 200 alone for
   the missing-view case, body-less; 204 + 403 for the US3 DELETE).
2. The `200` body for the JSON-template case equals the resolved
   jbuilder schema (asserted by parsing the same template via the
   public `JbuilderParser`).
3. The US2 GET operation has kind `:html_page` (vendor extension
   `x-renders-html: true`), `text/html` content type, no
   `application/json` entry.
4. The missing-view action's 200 entry has no `content` key.
5. The DELETE operation's 403 entry has the resolved
   `forbidden.json.jbuilder` schema, and the operation classifies as
   `:json` (because the 403 render is JSON-shaped, even though the
   happy path is `head :no_content`).
6. `GenerationReport.warnings` contains no
   "response shape could not be determined" entries for any of the
   above.

## 3. Regression check — existing single-render operations unchanged

```bash
bundle exec rspec spec/integration/feature_001_regression_spec.rb \
                  spec/integration/html_page_endpoints_spec.rb \
                  spec/integration/response_bodies_spec.rb
```

The existing HTML-page and jbuilder-view integration specs must
continue to pass byte-identically — operations whose only render is a
single action-body template render produce the same single-entry
response (SC-004).

## 4. Validate against OpenAPI 3.1 schema

```bash
bundle exec rspec spec/integration/generate_all_endpoints_spec.rb
```

The fixture document (now containing the new
`api/template_renders/...` operations) must still pass schema
validation.

## 5. Determinism check

```bash
bundle exec rspec spec/integration/determinism_spec.rb
```

Multi-status responses produced from template-render sites — including
the `oneOf` ordering when a jbuilder schema and a `render json:` shape
collide at one status — must be byte-identical across two consecutive
runs.

## 6. Manual smoke check against a real app (optional)

```bash
cd path/to/some-rails-app
bundle exec rails-openapi-generator generate --out /tmp/openapi.yaml
```

Find an action whose happy path is a `render "..."` template call
inside a helper (or a `render_show` / `render_order` pattern). The
operation's `responses` map should now include the happy-path status
with the resolved jbuilder schema (or no body if the view doesn't
exist), in addition to any error-status entries from JSON renders.
