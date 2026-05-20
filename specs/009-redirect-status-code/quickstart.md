# Quickstart: Redirect Response Status Code

A short end-to-end check that the redirect classification works once the
feature is implemented. Run from the gem's repository root.

## 1. Confirm the dummy fixture has redirect actions

The fixture under `spec/fixtures/dummy/app/controllers/api/redirects_controller.rb`
should expose at least:

- A `POST` action whose body is `redirect_to some_path` (default `302`).
- A `POST` action whose body is `redirect_to some_path, status: :see_other`
  (`303`).
- A `GET` action whose body is `redirect_to root_path, status: 301`.
- A `POST` action whose body is `redirect_back_or_to fallback_path` (`302`).
- A `POST` action that does both `render json: { … }` and `redirect_to`
  (asserting JSON precedence — redirect must not win).

Each action must have a matching route in
`spec/fixtures/dummy/config/routes.rb`.

## 2. Generate the document against the dummy app

```bash
bundle exec rspec spec/integration/redirect_response_spec.rb
```

The integration spec generates the dummy app's OpenAPI document into memory
and asserts:

1. The bare-redirect action's response is filed under `'302'` with no
   `content`.
2. The `:see_other` action's response is filed under `'303'`.
3. The `status: 301` action's response is filed under `'301'`.
4. The `redirect_back_or_to` action's response is filed under `'302'`.
5. The mixed `render json:` + `redirect_to` action's response is filed under
   the JSON-render status (200/201) with an `application/json` body —
   redirect is ignored.
6. The `GenerationReport.warnings` list contains **no** entry of the form
   `"<method> <path>: response shape could not be determined"` for any of
   the redirect actions above.

## 3. Validate the document against the OpenAPI 3.1 schema

The existing `spec/integration/generate_all_endpoints_spec.rb` already
validates the fixture document against the OpenAPI 3.1 schema. After this
feature lands, that spec must still pass:

```bash
bundle exec rspec spec/integration/generate_all_endpoints_spec.rb
```

## 4. Determinism check

Repeated runs on unchanged input must produce byte-identical output. The
existing `spec/integration/determinism_spec.rb` covers this; it must
continue to pass:

```bash
bundle exec rspec spec/integration/determinism_spec.rb
```

## 5. Manual smoke check against a real app (optional)

```bash
cd path/to/some-rails-app
bundle exec rails-openapi-generator generate --out /tmp/openapi.yaml
grep -A 2 "/parent_folders:" /tmp/openapi.yaml
```

The `POST /parent_folders` operation, which previously showed status `'201'`
with an `application/json` undeterminable body, should now show:

```yaml
      responses:
        '302':
          description: Successful response
```

…and the prior `POST /parent_folders: response shape could not be
determined` warning should be absent from the generator's stderr output.
