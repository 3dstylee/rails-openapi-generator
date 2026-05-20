---
description: "Task list for rescue_from Handlers"
---

# Tasks: rescue_from Handlers

**Input**: Design documents from `/specs/014-rescue-from-handlers/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks ARE included — Constitution Principle III
(Test-First Discipline) mandates every behavior change be covered by
an automated test written before/alongside implementation.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2, US3
P3). This feature extends the existing gem (features 001–013). The
scope is narrow: one new resolver, one line of Generator wiring, and
fixture additions confined to a new controller hierarchy to preserve
SC-004 byte-identity for existing endpoints.

## Path Conventions

Existing Ruby gem: runtime code in `lib/rails_openapi_generator/`,
tests in `spec/` with the dummy Rails app under `spec/fixtures/dummy/`.

---

## Phase 1: Setup

**Purpose**: Version bump, new controller hierarchy + concern + routes,
and the route-list assertion update

- [X] T001 Bump `VERSION` to `0.14.0` in `lib/rails_openapi_generator/version.rb` — rescue_from detection changes generated output (Constitution V)
- [X] T002 [P] Add `spec/fixtures/dummy/app/controllers/concerns/rescue_handlers_concern.rb` declaring `rescue_from ActionController::ParameterMissing, with: :bad_request_via_concern` and a private `bad_request_via_concern` method that does `render json: { error: "missing_param" }, status: :bad_request` (used by US3 to verify concern-declared handlers are picked up via `rescue_handlers`)
- [X] T003 [P] Add `spec/fixtures/dummy/app/controllers/api/error_rescuing_controller.rb` — a NEW base controller inheriting from `ApplicationController`. Declares three method-form handlers: `rescue_from ActiveRecord::RecordNotFound, with: :record_not_found` (renders `{ error: "not_found" }`, status `:not_found`); `rescue_from Pundit::NotAuthorizedError, with: :forbidden` (renders `{ error: "forbidden" }`, status `:forbidden`); `rescue_from ActionController::ParameterMissing, with: :handler_bad_request` (renders `{ error: "bad_request" }`, status `:bad_request`). Also declares ONE block-form handler for US2: `rescue_from ActiveRecord::RecordInvalid do |error| render json: { errors: error.record.errors }, status: :unprocessable_entity end`. Finally, `include RescueHandlersConcern` to wire US3. Define `Pundit::NotAuthorizedError = Class.new(StandardError)` as a local constant inside the dummy app's initializer if Pundit isn't loaded (so `rescue_from` resolves the class name without requiring the gem)
- [X] T004 [P] Add `spec/fixtures/dummy/app/controllers/api/rescued_resources_controller.rb` inheriting from `Api::ErrorRescuingController`. Expose a GET `show` action that does `param! :id, Integer, required: true; render json: { id: params[:id] }`. The action's own response is `200`; the inherited handlers contribute `400` (twice — once from the concern, once from the inherited base controller's handler — they'll union per feature 010), `403`, `404`, `422`
- [X] T005 Add routes for the new actions in `spec/fixtures/dummy/config/routes.rb`
- [X] T006 Update the `spec/integration/generate_all_endpoints_spec.rb` route-list assertion to include the new `rescued_resources` paths
- [X] T007 Define `Pundit::NotAuthorizedError` as a stand-in exception class (since the Pundit gem isn't a dependency) — either via an initializer in the dummy app or inline at the top of `error_rescuing_controller.rb`. Without this, the `rescue_from` declaration would fail at controller load time

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Add `RescueFromResolver` + `RescueFromHandler` struct + Generator wiring. No new `RenderSite` field, no new emission path.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Tests for the foundation ⚠️ (write first, must fail)

- [X] T008 [P] [Test] Add `spec/unit/rescue_from_resolver_spec.rb` covering: (a) `resolve(controller_class)` returns the resolved handlers in `rescue_handlers` order; (b) Symbol-form handler → returns a `RescueFromHandler` whose `method_node` is the method's AST (via `MethodResolver`); (c) Proc-form handler → returns a `RescueFromHandler` whose `method_node` is the block's body AST (via `proc.source_location` + Ripper); (d) handler whose method cannot be resolved → silently skipped (not returned); (e) controller class that doesn't respond to `rescue_handlers` → returns `[]`; (f) `nil` controller class → returns `[]`; (g) the same `(controller_class)` resolved twice → only one round of method/proc resolution (cache, asserted via identity comparison); (h) concern-declared handler shows up because `rescue_handlers` merges the chain
- [X] T009 [P] [Test] Extend `spec/unit/before_action_resolver_spec.rb` (or add a small sibling test) asserting that `BeforeActionResolver`'s existing `own_source_file` fallback strategy (per feature 008's fix using `Module.const_source_location`) still works — regression check, since we'll be loading new dummy fixture controllers and `instance_methods(false)` ordering must continue to be irrelevant

### Implementation for the foundation

- [X] T010 Add `RescueFromHandler` Struct and `RescueFromResolver` class in `lib/rails_openapi_generator/rescue_from_resolver.rb`. Public surface: `RescueFromHandler = Struct.new(:exception_name, :method_node, keyword_init: true)`; `RescueFromResolver.new(method_resolver:)` and `#resolve(controller_class)`. Implementation: returns `[]` for nil / non-responding classes; iterates `controller_class.rescue_handlers` (an Array of `[exception_class_string, Symbol|Proc]`); for each entry, dispatches on `handler.is_a?(Symbol)` vs `handler.is_a?(Proc)` to resolve the body; silently skips unresolvable handlers; caches by `controller_class.object_id` (or controller_class itself as a Hash key); rescues `StandardError` and returns `[]` from the outer call if anything blows up
- [X] T011 Implement Symbol-handler resolution inside `RescueFromResolver`: delegate to `@method_resolver.resolve(controller_class, method_name)`. On a non-nil `ResolvedMethod`, build `RescueFromHandler.new(exception_name: exception_class_string, method_node: resolved.node)`. On nil, skip
- [X] T012 Implement Proc-handler resolution inside `RescueFromResolver`: read `handler.source_location` → `[file, line]`; return nil if either is missing or file is unreadable. Parse the file via Ripper (or reuse `YardParser` if it exposes a raw-AST method; otherwise call `Ripper.sexp(File.read(file))` directly). Walk the AST for a `:method_add_block` node whose call is `rescue_from` (the `:command` with ident "rescue_from") AND whose block AST node's first source line equals the captured `line`. When matched, return the block's body AST node (the `:bodystmt` inner-statements for `:do_block`, or the body for `:brace_block`)
- [X] T013 Require the new file in `lib/rails_openapi_generator.rb`: add `require_relative "rails_openapi_generator/rescue_from_resolver"` next to the other requires (alphabetically near `before_action_resolver`)
- [X] T014 Wire `RescueFromResolver` into `Generator#setup_pipeline` in `lib/rails_openapi_generator/generator.rb`: instantiate `@rescue_from_resolver = RescueFromResolver.new(method_resolver: @method_resolver)` alongside the other resolvers
- [X] T015 Extend `Generator#collect_extra_sites` in `lib/rails_openapi_generator/generator.rb` to ALSO collect `rescue_from_render_sites(controller_class)` and concat them to the returned list. Add the new method: for each `RescueFromHandler` returned by `@rescue_from_resolver.resolve(controller_class)`, walk via `@walker.reachable_bodies(controller_class, handler.method_node)`, flat_map each body through `@render_extractor.collect_sites(body, source: :rescue_from)`

**Checkpoint**: The full existing suite still passes (SC-004 — no fixtures gain new entries because the new controller hierarchy is isolated); the resolver works on the new `Api::ErrorRescuingController`

---

## Phase 3: User Story 1 - Standard rescue_from handlers from ApplicationController (Priority: P1) 🎯 MVP

**Goal**: An operation on a controller inheriting from a base with `rescue_from FooError, with: :handler_method` declarations gains response entries for each handler's render status, with the handler's literal body shape.

**Independent Test**: Generate against the dummy app and confirm the `rescued_resources#show` operation has the action's `200` entry PLUS `403`, `404`, `400` from the three method-form handlers. Each entry has the literal `{ error: "string" }` body shape.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T016 [P] [US1] Add `spec/integration/rescue_from_handlers_spec.rb` asserting: the `rescued_resources#show` operation has response keys `["200", "400", "403", "404", "422"]` (a superset that includes both action-body and handler-derived statuses); each handler-derived status carries the handler's literal body schema (e.g. `404` has `{type: object, properties: {error: {type: string}}}`)
- [X] T017 [P] [US1] Extend `spec/integration/rescue_from_handlers_spec.rb` asserting that the GenerationReport emits NO new warnings for the rescued_resources route beyond what was already there (the rescue_from path is silent on success)

### Implementation for User Story 1

No new implementation — T010–T015 (foundation) already delivers this story. T016–T017 verify it end-to-end.

**Checkpoint**: MVP — every action on every controller inheriting from `Api::ErrorRescuingController` gains the documented error responses

---

## Phase 4: User Story 2 - Block-form rescue_from handlers (Priority: P2)

**Goal**: A `rescue_from FooError do |error| render json: ..., status: :foo end` block contributes a response entry the same as a method-form handler.

**Independent Test**: The `rescued_resources#show` operation includes the `422` entry from the block-form `RecordInvalid` handler, with the block's literal `{ errors: {} }` body shape.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T018 [P] [US2] Extend `spec/integration/rescue_from_handlers_spec.rb` asserting: the `rescued_resources#show` operation has a `422` entry whose body schema is `{type: object, properties: {errors: {}}}` (the `errors:` key with permissive value, since `error.record.errors` is non-literal)
- [X] T019 [P] [US2] Extend `spec/unit/rescue_from_resolver_spec.rb` asserting that a `Proc` handler's `method_node` is the AST for the block's body — assert that walking it via `RenderExtractor.collect_sites` produces the expected render site (status 422, schema with `errors` key)

### Implementation for User Story 2

No new implementation — T012 (Proc-handler resolution) already delivers this story. T018–T019 verify the proc walking and end-to-end emission.

**Checkpoint**: Block-form handlers are documented

---

## Phase 5: User Story 3 - Concern-declared rescue_from (Priority: P3)

**Goal**: A `rescue_from` declaration inside a concern that's included into the base controller contributes the same as one declared directly on the base.

**Independent Test**: The concern declares `rescue_from ParameterMissing, with: :bad_request_via_concern` and the handler renders `{ error: "missing_param" }`. The `rescued_resources#show` operation gains this entry alongside the directly-declared `400` from `handler_bad_request`. Both shapes union at the `400` status per feature 010 (`oneOf` of two literal shapes).

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T020 [P] [US3] Extend `spec/integration/rescue_from_handlers_spec.rb` asserting: the `rescued_resources#show` operation's `400` entry is documented (either as the concern's `{ error: "missing_param" }` shape, the base controller's `{ error: "bad_request" }` shape, or a `oneOf` of both — assert the keys/types are present without over-specifying the exact union form; the union is feature 010's responsibility)
- [X] T021 [P] [US3] Extend `spec/unit/rescue_from_resolver_spec.rb` asserting that `resolver.resolve(Api::ErrorRescuingController)` returns the concern-declared handler alongside the directly-declared ones (proves `rescue_handlers` merges the chain and the resolver picks up everything)

### Implementation for User Story 3

No new implementation — `rescue_handlers` already returns the merged chain (parent + concern + own), and the resolver walks all of them uniformly. T020–T021 verify the concern-inheritance path end-to-end.

**Checkpoint**: Concerns contribute their handlers; the full user-reported pattern is supported

---

## Phase 6: Edge Cases (validation)

**Purpose**: Verify the spec's edge-case rules with focused assertions.

- [X] T022 [P] [US1] Extend `spec/integration/rescue_from_handlers_spec.rb` asserting that a controller WITHOUT any `rescue_from` on its chain (e.g. `Api::UsersController` inheriting directly from `ApplicationController`) emits BYTE-IDENTICAL responses to its 0.13.0 output — the new walker does not contribute anything (SC-004)
- [X] T023 [P] [US1] Extend `spec/unit/rescue_from_resolver_spec.rb` asserting: an unresolvable method-form handler (declared via `with: :method_does_not_exist`) is silently skipped — `resolve(controller_class)` returns the OTHER handlers without raising
- [X] T024 [P] [US1] Extend `spec/integration/rescue_from_handlers_spec.rb` asserting that determinism holds: the `rescued_resources#show` operation's `responses` map is byte-identical across two consecutive runs (status ordering, handler-body schema ordering, `oneOf` ordering on the 400 union)

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Hardening, docs, regression, RuboCop

- [X] T025 [P] [Test] Extend `spec/integration/feature_001_regression_spec.rb` to assert SC-004: existing fixture endpoints (api/users#index, api/posts, api/redirects/*, api/template_renders/*, etc.) emit byte-identical responses to `0.13.0` — none of them should gain rescue_from-derived entries because their controller class chains don't include any `rescue_from` declarations
- [X] T026 [P] [Test] Extend `spec/integration/determinism_spec.rb`: the `rescued_resources#show` operation's responses are byte-identical across two consecutive runs
- [X] T027 [P] Update `README.md`'s response-detection section with a paragraph on `rescue_from` handler detection — covers method-form + block-form, inherited from parents and concerns, silent skip on unresolvable handlers, and the SC-004 byte-identical guarantee for controllers without `rescue_from` on the chain
- [X] T028 [P] Add a `0.14.0` entry to `CHANGELOG.md` describing `rescue_from` handler detection: the rescue_handlers chain reading, method-form + block-form support, inheritance from parents and concerns, the silent-skip rule, and the SC-004 byte-identical guarantee for existing endpoints
- [X] T029 Run `quickstart.md` end-to-end against the dummy app and correct any discrepancies
- [X] T030 [P] Run RuboCop across the changed `lib/` files and resolve offenses

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately. T003 depends on T002 (controller includes the concern). T004 depends on T003 (inherits from the new base). T005 depends on T004 (routes reference the new controller). T006 depends on T005 (route-list assertion needs the routes to exist). T007 must land before T003 (the controller's `rescue_from Pundit::NotAuthorizedError` would fail at class-load time without the stand-in)
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories. T008/T009 (tests) before T010–T015 (implementation); T010 (resolver class + struct) before T011/T012 (handler-form-specific resolution); T013 (require) before T014 (Generator references the class); T014 (instantiation) before T015 (wiring uses the instance)
- **User Stories (Phase 3–5)**: All depend on Foundational completion
- **Edge Cases (Phase 6)**: Depend on Foundational; can run in parallel with US1/US2/US3 verification
- **Polish (Phase 7)**: Depends on all targeted user stories

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — the MVP, no new implementation (T016–T017 are verification only)
- **US2 (P2)**: Depends on US1 — no new implementation; T012 (Proc-handler resolution) is part of the foundation; T018–T019 verify end-to-end
- **US3 (P3)**: Depends on US1 — no new implementation; `rescue_handlers` already merges the concern chain; T020–T021 verify end-to-end

### Within Each Phase

- Tests written first and failing before implementation (Constitution III)
- T010 (resolver class) before T011/T012 (per-form resolution methods)
- T013 (require) before T014 (Generator references ConstantResolver — wait, RescueFromResolver — sorry, the new class)
- T014 (instantiation) before T015 (wiring uses the resolver instance)

### Parallel Opportunities

- Setup: T002/T003/T004 are sequential (T003 includes T002's concern; T004 inherits T003); T005/T006 sequential after T004; T007 must precede T003. T002 and the concern setup can be done first, then the controller hierarchy
- Foundational tests: T008 and T009 parallel before T010–T015
- US1 verification: T016, T017 parallel
- US2 verification: T018, T019 parallel
- US3 verification: T020, T021 parallel
- Edge cases: T022, T023, T024 parallel
- Polish: T025, T026, T027, T028, T030 parallel; T029 sequential at the end

---

## Parallel Example: Foundational tests (Phase 2)

```bash
Task: "Add spec/unit/rescue_from_resolver_spec.rb covering Symbol-form, Proc-form, unresolvable-skip, cache, concern-inheritance"
Task: "Extend spec/unit/before_action_resolver_spec.rb regression check for own_source_file"
```

Both must FAIL (or pass-by-coincidence — T009 is a regression check) before T010–T015 are started.

## Parallel Example: User Story 1 integration

```bash
Task: "rescued_resources#show documents all five status entries from action + 3 method-form handlers + block-form handler"
Task: "GenerationReport emits no new warnings for the rescued_resources route"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (new controller hierarchy + concern + routes + stand-in exception class)
2. Complete Phase 2: Foundational (`RescueFromResolver` + Generator wiring)
3. Complete Phase 3: User Story 1 (verification — assert the three method-form handlers contribute)
4. **STOP and VALIDATE**: `rescued_resources#show` documents `403`/`404`/`400` from the inherited handlers
5. Demo the MVP — every action inheriting from a base with `rescue_from` gains the documented error responses

### Incremental Delivery

1. Setup + Foundational → rescue_from chain reading + handler-body extraction in place
2. US1 → method-form handlers documented (MVP — the user's reported pattern)
3. US2 → block-form handlers documented (Proc.source_location + AST search)
4. US3 → concern-declared handlers verified (free via `rescue_handlers` chain merge)
5. Edge Cases → unresolvable-skip + determinism + SC-004
6. Polish → README, CHANGELOG, RuboCop

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T010–T015 are tightly coupled)
2. Once Foundational is done:
   - Developer A: US1 + edge cases T022 (SC-004 regression)
   - Developer B: US2 + Proc handler edge cases
   - Developer C: US3 (concern integration) + README/CHANGELOG
3. Polish converges last

---

## Notes

- [P] = different files, no dependency on an incomplete task
- [US#] maps a task to its user story; [Test] marks a non-story test task
- All test specs MUST fail before their implementation task is started
- This feature is purely additive at the per-operation level for any
  endpoint whose controller class chain has NO `rescue_from`
  declarations — those endpoints MUST produce byte-identical output
  to `0.13.0` (SC-004, T022/T025)
- Re-raising handlers, dynamic-status handlers, and exception-implied
  statuses without an explicit `rescue_from` are deferred per FR-009
  / Edge Cases; do not add them here
- The `Pundit::NotAuthorizedError` exception class in the fixture is
  a stand-in (we don't add Pundit as a dependency); declare it
  manually before the controller file loads
- Commit after each task or logical group
