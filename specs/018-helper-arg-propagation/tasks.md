---
description: "Task list for feature 018 — Helper argument propagation"
---

# Tasks: Helper argument propagation

**Input**: Design documents from `/specs/018-helper-arg-propagation/`
**Prerequisites**: plan.md, spec.md

## Phase 1: Setup

- [X] T001 Bump `VERSION` to `0.18.0` in `lib/rails_openapi_generator/version.rb`
- [X] T002 Add `spec/fixtures/dummy/app/controllers/api/binding_helpers_controller.rb` with three actions exercising US1 (positional), US2 (multi-level), US3 (kwargs)
- [X] T003 Add routes for the new actions in `spec/fixtures/dummy/config/routes.rb`
- [X] T004 Update the `spec/integration/generate_all_endpoints_spec.rb` route-list assertion

## Phase 2: Unit tests (write first, must fail)

- [X] T005 Add `spec/unit/helper_binding_walker_spec.rb` covering:
  (a) positional arg binding — call `f(1, "x")` against `def f(a, b)` binds `a→1, b→"x"`;
  (b) kwarg binding — `f(status: :created)` against `def f(status:)` binds `status→:created`;
  (c) AST substitution of a `:var_ref` to `:@ident` only when name is bound (others left untouched);
  (d) multi-level propagation — outer literal substituted into the inner call's binding;
  (e) max-depth termination on a self-cycle helper;
  (f) bodies do NOT include the root node itself.

## Phase 3: Implementation

- [X] T006 Create `lib/rails_openapi_generator/helper_binding_walker.rb` with the new class. Public API: `reachable_bodies(controller_class, root)` returning an Array of substituted helper bodies. Internal: `param_names(def_node)` → `{positional: [...], keyword: [...]}`; `bind_args(def_node, args)` → `Hash<String, node>`; `substitute(node, bindings)` → deep-copied AST with `:var_ref → :@ident` swapped for bound names.
- [X] T007 Require the new file from `lib/rails_openapi_generator.rb`
- [X] T008 Wire the walker into `Generator`:
  - `@helper_binding_walker = HelperBindingWalker.new(method_resolver: @method_resolver, max_depth: @configuration.method_resolution_depth)`
  - Update `helper_render_sites` to use `@helper_binding_walker.reachable_bodies(controller_class, action_node)` (no `.drop(1)` — the walker already excludes the root).
  - Update `before_action_render_sites` and `rescue_from_render_sites` similarly: collect the callback / handler body directly, then concat the walker's bodies.

**Checkpoint**: T005 unit tests pass; full suite remains green.

## Phase 4: Integration tests

- [X] T009 Add `spec/integration/feature_018_helper_arg_propagation_spec.rb` with:
  - US1: the create action's `rescue` clause calling `render_error("msg", 422, :unprocessable_entity)` documents a 422 entry with the literal hash schema.
  - US2: action calls `outer_helper(:ok)` → `outer_helper` calls `inner_helper(status)` → `inner_helper` does `head status` → 200 documented.
  - US3: action calls `respond(json: {ok: true}, status: :created)` and the helper renders with those kwargs — 201 documented with `ok: boolean` schema.

## Phase 5: Polish

- [X] T010 [P] Extend `spec/integration/feature_001_regression_spec.rb` to assert SC-003 — operations whose helpers don't use parameter-dependent renders are byte-identical to `0.17.0`.
- [X] T011 [P] Extend `spec/integration/determinism_spec.rb` with a stability case for the new binding-helpers fixture.
- [X] T012 [P] Update `README.md` with a paragraph on argument propagation in the response-bodies section.
- [X] T013 [P] Add `0.18.0` entry to `CHANGELOG.md`.
- [X] T014 Run RuboCop on changed files; resolve offenses.
- [X] T015 Run the full suite under two seeds; confirm zero failures.
