# Quickstart: Multi-Status Responses

A short end-to-end check that the multi-status response feature works
once implemented. Run from the gem's repository root.

## 1. Confirm the dummy fixture exercises every scenario

`spec/fixtures/dummy/app/controllers/api/multi_status_controller.rb`
should expose:

- A `PATCH` action that does a happy `render json: <method_call>` and a
  guard `render json: <hash>, status: :unprocessable_entity` (the
  motivating case — two body-less / body entries, no warning).
- A `POST` action that does two `render json:` calls at the same status
  with **identical** shapes (collapses to one entry — no `oneOf`).
- A `POST` action that does two `render json:` calls at the same status
  with **distinct literal** shapes (collapses to one entry with
  `oneOf` of the two unique schemas, sorted).
- A `POST` action that does `head :ok` and `render json: { id: 1 }`
  (collapses to a single `200` entry with the render's body).
- A `PATCH` action whose controller includes a concern with
  `before_action :authenticate` doing a 401 render — that action's
  operation must show a `401` entry without the action body mentioning
  `authenticate`.
- A controller declaring `before_action :require_admin, only: [:destroy]`
  on its own source — only the `destroy` operation gets the
  `before_action`'s entry; the other actions don't.

A concern under `spec/fixtures/dummy/app/controllers/concerns/auth_callback.rb`
provides the `before_action :authenticate` declaration and the
`authenticate` method.

## 2. Generate the document against the dummy app

```bash
bundle exec rspec spec/integration/multi_status_responses_spec.rb
```

The integration spec generates the dummy app's OpenAPI document into
memory and asserts, for each fixture action:

1. The set of `responses` keys (the documented statuses).
2. The `content` / no-content shape of each entry.
3. `oneOf` ordering on the union case (canonical-JSON-ascending,
   duplicates removed).
4. The `head + render` collapse (one entry with the render's body, no
   `oneOf`, no second entry).
5. The `before_action` chain: the 401 entry appears on the actions the
   callback applies to and not on those it does not (per `only:` /
   `except:` literal-array recovery).
6. The `GenerationReport.warnings` list contains no
   `"response shape could not be determined"` entries for the multi-
   status actions.

## 3. Validate the document against the OpenAPI 3.1 schema

```bash
bundle exec rspec spec/integration/generate_all_endpoints_spec.rb
```

The existing fixture-document validation must continue to pass with
multi-entry responses (including `oneOf` schemas) present.

## 4. Regression check: single-render operations unchanged

```bash
bundle exec rspec spec/integration/feature_001_regression_spec.rb
```

Operations whose action contains exactly one `render json:`, or one
`head`, or one `redirect_to`, or that are JSON-via-view, or HTML-page,
or file-download, must emit byte-identical output to `0.8.0` (SC-005).

## 5. Determinism check

```bash
bundle exec rspec spec/integration/determinism_spec.rb
```

Multi-status entries (including the `oneOf` list ordering) must be
byte-identical across repeated runs.

## 6. Manual smoke check against a real app (optional)

```bash
cd path/to/some-rails-app
bundle exec rails-openapi-generator generate --out /tmp/openapi.yaml
```

Find an action that has both a happy `render json:` and a guard
`render json:, status: :unprocessable_entity` (or a similar error
status). The operation's `responses` map should now contain both the
happy status (e.g. `200` or `201`) and the error status (e.g. `422`),
each with the schema of the corresponding render (or no `content` when
the render's argument is non-literal). The prior
`"response shape could not be determined"` warning, when produced only
because the body shape was non-literal, should be absent.
