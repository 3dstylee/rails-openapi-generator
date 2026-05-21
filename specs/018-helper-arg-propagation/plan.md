# Plan: Feature 018 — Helper argument propagation

## Tech context

- Ruby gem; Ripper AST static analysis. Constitution V → MINOR bump
  (`0.17.0` → `0.18.0`).
- New class `HelperBindingWalker` in
  `lib/rails_openapi_generator/helper_binding_walker.rb`. Touches
  `Generator` (replace the three helper-site collectors).

## Architecture

### Pieces

1. **Parameter extraction** — read a `[:def, ident, paren_params, bodystmt]`
   node's parameter list (Ripper's `:params` node). For v1: required
   positional names, optional positional names, and required+default
   keyword names. Splats/blocks omitted from the binding map.
2. **Argument binding** — given a helper's positional + kwarg call args,
   produce a `Hash<String, ast_node>` mapping param-name → arg AST node.
   Non-literal args bind too (their substitution into the body simply
   stays UNRESOLVED on evaluation — matches today's behavior).
3. **AST substitution** — deep-walk the helper body and replace every
   `[:var_ref, [:@ident, name]]` (and `[:var_field, ...]` for
   assignment LHS to avoid clobbering) where `name` is bound, with
   the bound AST node. Returns a new AST (does not mutate input).
4. **Walker** — `HelperBindingWalker#reachable_bodies(controller_class,
   root)` walks every receiverless call in `root`, resolves each via
   `MethodResolver`, binds the call's args to the helper's params,
   substitutes, and recurses into the substituted body. Returns the
   list of substituted bodies (matching the existing
   `ControllerMethodWalker.reachable_bodies(...).drop(1)` shape).

### Walker design

- Bounded by `max_depth` (default 5; injected via `Configuration`).
- No per-location visited set: each call site is walked independently
  so a helper called twice with different literals contributes two
  substituted bodies. Cycles terminate via `max_depth`.
- Composes through nesting because substitution happens **before**
  the recursive walk descends into the substituted body — so a nested
  call's args have already had outer-param refs replaced.

### Generator wiring

- Replace `helper_render_sites`, `before_action_render_sites`, and
  `rescue_from_render_sites` to use `@helper_binding_walker` in place
  of `@walker` for descendant collection. Each callback / handler's
  own body is collected directly (no bindings at the callback level —
  Rails calls these).
- Keep the existing `ControllerMethodWalker` for unchanged callers
  (`wrapper_download_resolver`, `implicit_params_scanner`) — they
  walk bodies without needing argument propagation.

## Constitution check

- **I (Simplicity / YAGNI)**: PASS — one new ~120-line class, three
  one-line wire-up changes in Generator. No new abstractions in
  RenderExtractor or LiteralEvaluator.
- **III (Test-First)**: PASS — unit tests for parameter extraction,
  argument binding, AST substitution, and walker composition before
  the production code lands; one integration fixture per user story.
- **V (Versioned BC Output)**: PASS — operations whose helpers contain
  no parameter-dependent renders emit byte-identical schemas to
  `0.17.0` (regression coverage).

## Files touched

- `lib/rails_openapi_generator/version.rb` — `0.17.0` → `0.18.0`
- `lib/rails_openapi_generator/helper_binding_walker.rb` — new
- `lib/rails_openapi_generator.rb` — require the new file
- `lib/rails_openapi_generator/generator.rb` — wire the new walker
- `spec/unit/helper_binding_walker_spec.rb` — unit tests for the
  walker, binding rules, and substitution
- `spec/integration/feature_018_helper_arg_propagation_spec.rb` — US1,
  US2, US3 end-to-end
- `spec/integration/feature_001_regression_spec.rb` — assert
  byte-identical output for operations whose helpers don't use the new
  shape
- `spec/integration/determinism_spec.rb` — stability case
- `spec/integration/generate_all_endpoints_spec.rb` — route list update
- `spec/fixtures/dummy/app/controllers/api/binding_helpers_controller.rb`
  — new fixture exercising all three stories
- `spec/fixtures/dummy/config/routes.rb` — wire routes
- `README.md` — note the new behavior
- `CHANGELOG.md` — `0.18.0` entry
