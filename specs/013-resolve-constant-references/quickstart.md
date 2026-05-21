# Quickstart: Resolve Constant References

A short end-to-end check that constant resolution works once
implemented. Run from the gem's repository root.

## 1. Confirm the dummy fixture defines constants and uses them

`spec/fixtures/dummy/app/services/auto_photo_vhs/
enqueue_furniture_generation_service.rb` defines:

- `MOODS = %w[modern classic minimalist scandinavian industrial].freeze`
- `PAGE_RANGE = 1..100`
- `EMAIL_PATTERN = /\A[^@\s]+@[^@\s]+\z/`
- `CLASS_REF = String` (a class — non-schema-compatible)

`spec/fixtures/dummy/app/controllers/api/
constant_references_controller.rb` exposes:

- `POST execute`: `param! :mood, String, in:
  AutoPhotoVhs::EnqueueFurnitureGenerationService::MOODS`, plus a
  nested `param! :moods, Array do |p, i| p.param! i, String, in:
  ...::MOODS; end`
- `GET range`: `param! :page, Integer, in:
  AutoPhotoVhs::EnqueueFurnitureGenerationService::PAGE_RANGE`
- `GET pattern`: `param! :email, String, format:
  AutoPhotoVhs::EnqueueFurnitureGenerationService::EMAIL_PATTERN`
- `GET non_compatible`: `param! :x, String, in:
  AutoPhotoVhs::EnqueueFurnitureGenerationService::CLASS_REF` —
  silently dropped, warning fires
- `GET missing`: `param! :x, String, in: NotAConstantAtAll` —
  same fallback path

## 2. Generate the document against the dummy app

```bash
bundle exec rspec spec/integration/constant_references_spec.rb
```

The integration spec asserts, per fixture action:

1. The `execute` operation documents `mood` as a request-body
   parameter with `enum: ["modern", "classic", "minimalist",
   "scandinavian", "industrial"]`.
2. The same `execute` operation documents `moods.items` as
   `type: "string", enum: [<same list>]`.
3. The `range` operation documents `page` with `minimum: 1` and
   `maximum: 100`.
4. The `pattern` operation documents `email` with the regex
   source as `pattern`.
5. The `non_compatible` operation documents `x` without an
   `enum`; the warning "non-literal param! arguments for x"
   fires for that route.
6. The `missing` operation documents `x` without an `enum`; the
   warning fires; no exception is raised.

## 3. Regression check — operations without constant references unchanged

```bash
bundle exec rspec spec/integration/feature_001_regression_spec.rb \
                  spec/integration/parameters_from_validations_spec.rb \
                  spec/integration/implicit_params_spec.rb
```

The existing `param!` and parameter-emission integration specs
must continue to pass byte-identically — operations whose
`param!` calls have always been fully literal in the source
emit the same parameter schemas as in `0.11.0` (SC-004).

## 4. Validate against OpenAPI 3.1 schema

```bash
bundle exec rspec spec/integration/generate_all_endpoints_spec.rb
```

The fixture document (now with constant-derived `enum`,
`minimum`/`maximum`, and `pattern`) must pass schema validation.

## 5. Determinism check

```bash
bundle exec rspec spec/integration/determinism_spec.rb
```

The `execute` operation's `enum` list — including its order —
must be byte-identical across two consecutive runs. (The order
matches the constant's value order in Ruby, which is stable.)

## 6. Manual smoke check against a real app (optional)

```bash
cd path/to/some-rails-app
bundle exec rails-openapi-generator generate --out /tmp/openapi.yaml
```

Find an action that uses `param! ..., in: Module::CONSTANT`. The
generated parameter schema should now show the constant's actual
values in its `enum`. The
`non-literal param! arguments for <name>` warning should be
absent for that parameter (assuming the constant resolves and is
schema-compatible).
