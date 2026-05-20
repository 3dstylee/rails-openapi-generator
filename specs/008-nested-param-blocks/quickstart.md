# Quickstart: Nested Parameter Blocks

A short end-to-end check that nested `param!` block detection
works once implemented. Run from the gem's repository root.

## 1. Confirm the dummy fixture exercises every scenario

`spec/fixtures/dummy/app/controllers/api/nested_params_controller.rb`
should expose:

- A `POST search` action with `param! :q, Hash do |q| q.param!
  :keyword, String; q.param! :page, Integer, in: 1..100; end`
  (US1 — Hash with scalar fields).
- A `POST tags` action with `param! :tags, Array do |a, i|
  a.param! i, String; end` (US2 — Array of strings, no constant).
- A `POST moods` action that combines feature 013 + 008: `param!
  :moods, Array do |p, i| p.param! i, String, in:
  AutoPhotoVhs::EnqueueFurnitureGenerationService::MOODS; end`
  (the user's reported case — Array of strings with a constant
  `in:`).
- A `POST nested` action with a Hash containing a Hash containing
  a scalar (US3 — deep nesting).
- A `POST empty_block` action with `param! :h, Hash do |q| end`
  (FR-007 — empty block falls back to bare object).
- A `POST non_hash_block` action with `param! :name, String do |s|
  s.param! :ignored, Integer end` (FR-008 — block on non-Hash/Array
  type is ignored).

## 2. Generate the document against the dummy app

```bash
bundle exec rspec spec/integration/nested_param_blocks_spec.rb
```

The integration spec asserts, per fixture action:

1. The `search` action's `q` property is `{ type: object,
   properties: { keyword: { type: string }, page: { type:
   integer, minimum: 1, maximum: 100 } } }`.
2. The `tags` action's `tags` property is `{ type: array,
   items: { type: string } }`.
3. The `moods` action's `moods` property is `{ type: array,
   items: { type: string, enum: [<MOODS values>] } }` — the
   constant resolution inherited from feature 013 lights up here.
4. The `nested` action documents all three levels of nesting in
   the schema.
5. The `empty_block` action's `h` property is `{ type: object }`
   (bare — FR-007).
6. The `non_hash_block` action's `name` property is `{ type:
   string }` (block ignored — FR-008).
7. `GenerationReport.warnings` contains no spurious entries
   from the new walker — only the expected "non-literal
   param! arguments" warnings for genuinely-unresolved nested
   args (and only on those specific nested names).

## 3. Regression check — flat `param!` operations unchanged

```bash
bundle exec rspec spec/integration/parameters_from_validations_spec.rb \
                  spec/integration/feature_001_regression_spec.rb
```

The existing flat-`param!` integration specs must continue to
pass byte-identically (SC-005 / FR-009). Endpoints whose
`param!` calls have no block emit the same parameter schemas as
in `0.12.0`.

## 4. Validate against OpenAPI 3.1 schema

```bash
bundle exec rspec spec/integration/generate_all_endpoints_spec.rb
```

The fixture document — now with nested object/array schemas —
must pass schema validation.

## 5. Determinism check

```bash
bundle exec rspec spec/integration/determinism_spec.rb
```

Nested `properties:` orderings must be byte-identical across
two consecutive runs (alphabetical, matching the existing flat
sort).

## 6. Depth-bound check (US3 safety)

The `nested` action goes three levels deep. With the default
`method_resolution_depth: 5`, all three are documented.

To exercise the bound, temporarily set `config.method_resolution_depth
= 1` and re-run; the depth-2 and depth-3 subtrees should fall back
to bare object/array schemas without raising.

## 7. Manual smoke check against a real app (optional)

```bash
cd path/to/some-rails-app
bundle exec rails-openapi-generator generate --out /tmp/openapi.yaml
```

Find an action that uses `param! ..., Hash do |q| q.param! ... end`
or `param! ..., Array do |a, i| a.param! i, ... end`. The
parameter schema should now show the full structure — object
properties for Hash, array items for Array.
