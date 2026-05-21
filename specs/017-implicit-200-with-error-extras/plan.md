# Plan: Feature 017 — Implicit 200 with error extras

## Tech context

- Ruby gem, Ripper AST static analysis. Constitution V → MINOR bump
  (`0.16.0` → `0.17.0`).
- One-file production change in
  [lib/rails_openapi_generator/response_builder.rb](../../lib/rails_openapi_generator/response_builder.rb)
  (≤10 lines added).

## Architecture

Production change: extend `ResponseBuilder#undeterminable_response`. When
`render_result.render_sites.empty?` (the action source contributes no
render site) AND `entries` lacks an entry at the convention status,
synthesize a body-less entry at the convention status and re-sort.

Naturally enforced invariants:

- An action with any render site (`render :template`, `head :ok`,
  `render json:`, `render html:`) keeps its existing behavior — the new
  branch is gated on `render_result.render_sites.empty?`.
- An action with a resolvable JSON view classifies as `:json` (not
  `:undeterminable`) and goes through `json_response`, which already has
  `integrate_view_schema` covering the multi-entry shape.
- The new entry is body-less (`body: nil`); DocumentBuilder already emits a
  body-less response shape for entries with no body.

## Constitution check

- **I (Simplicity / YAGNI)**: PASS — ≤10 lines, no new helper class, no
  new abstractions.
- **III (Test-First)**: PASS — unit tests in `response_builder_spec.rb`,
  integration test against a new fixture, written before the production
  change.
- **V (Versioned BC Output)**: PASS — purely additive. Templates without
  the new shape emit byte-identical output to `0.16.0`.

## Files touched

- `lib/rails_openapi_generator/version.rb` — `0.16.0` → `0.17.0`
- `lib/rails_openapi_generator/response_builder.rb` — the one change
- `spec/unit/response_builder_spec.rb` — unit tests for the new branch
- `spec/integration/feature_017_implicit_200_spec.rb` — end-to-end
- `spec/integration/feature_001_regression_spec.rb` — assert byte-identical
  schemas for `0.16.0`-shape operations
- `spec/integration/determinism_spec.rb` — assert stability
- `spec/integration/generate_all_endpoints_spec.rb` — route list update
- `spec/fixtures/dummy/app/controllers/api/silent_with_rescue_controller.rb`
  (new)
- `spec/fixtures/dummy/config/routes.rb` — wire the route
- `README.md` — note the new behavior
- `CHANGELOG.md` — `0.17.0` entry
