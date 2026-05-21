# Quickstart: rescue_from Handlers

A short end-to-end check that `rescue_from` detection works once
implemented. Run from the gem's repository root.

## 1. Confirm the dummy fixture exercises every scenario

- `spec/fixtures/dummy/app/controllers/api/error_rescuing_controller.rb` —
  a NEW base controller inheriting from `ApplicationController` with
  three `rescue_from` method-form handlers (`record_not_found` → 404,
  `forbidden` → 403, `bad_request` → 400), one block-form handler
  for US2 (a `rescue_from ActiveRecord::RecordInvalid do |e| ... end`
  rendering 422), and `include RescueHandlersConcern` for US3.
- `spec/fixtures/dummy/app/controllers/concerns/rescue_handlers_concern.rb` —
  declares an extra `rescue_from` for US3.
- `spec/fixtures/dummy/app/controllers/api/rescued_resources_controller.rb` —
  inherits from `Api::ErrorRescuingController`, exposes a `show`
  action that does `render json: { id: 1 }`. Every action on this
  controller gains the inherited handler entries.

Existing fixtures (UsersController, PagesController, etc.) inherit
from `ApplicationController` directly and stay unchanged.

## 2. Generate the document against the dummy app

```bash
bundle exec rspec spec/integration/rescue_from_handlers_spec.rb
```

The integration spec asserts, per fixture action:

1. The `rescued_resources#show` operation has the action's `200`
   entry PLUS `400`, `403`, `404`, `422` entries (one per handler
   on the class chain).
2. The handler bodies' literal schemas are correctly emitted (the
   `{ error: "string" }` shape for the three method-form handlers,
   the `{ errors: {} }` shape for the block-form).
3. The concern-declared handler (US3) is also present on the
   operation (proves `rescue_handlers` includes concern entries).
4. No "response shape could not be determined" or
   "non-literal param!" warnings are emitted for this route
   beyond what was already there.

## 3. Regression check — controllers without `rescue_from` unchanged

```bash
bundle exec rspec spec/integration/feature_001_regression_spec.rb \
                  spec/integration/parameters_from_validations_spec.rb \
                  spec/integration/response_bodies_spec.rb
```

Existing fixture controllers (`api/users`, `api/pages`, etc.)
inherit from `ApplicationController` directly. Their
`rescue_handlers` chains are empty, so SC-004 byte-identity holds.
Every existing assertion must continue to pass.

## 4. Validate against OpenAPI 3.1 schema

```bash
bundle exec rspec spec/integration/generate_all_endpoints_spec.rb
```

The fixture document — now with the inherited `400`/`403`/`404`/`422`
entries on the new hierarchy — must pass schema validation.

## 5. Determinism check

```bash
bundle exec rspec spec/integration/determinism_spec.rb
```

The `rescued_resources#show` operation's response keys and per-status
body shapes are byte-identical across two consecutive runs.

## 6. Manual smoke check against a real app (optional)

```bash
cd path/to/some-rails-app
bundle exec rails-openapi-generator generate --out /tmp/openapi.yaml
```

Find an action on a controller inheriting from `ApplicationController`.
The operation's `responses` map should now contain entries for
every status the `rescue_from` handlers render (typically 400, 401,
403, 404, 422 in a typical Rails API). If the app has no
`rescue_from` declarations, output is byte-identical to before.
