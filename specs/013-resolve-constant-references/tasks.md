---
description: "Task list for Resolve Constant References"
---

# Tasks: Resolve Constant References

**Input**: Design documents from `/specs/013-resolve-constant-references/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks ARE included — Constitution Principle III (Test-First
Discipline) mandates every behavior change be covered by an automated test
written before/alongside implementation.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2). This
feature extends the existing gem (features 001–012). The scope is narrow:
add a `ConstantResolver` class, three new AST cases in `LiteralEvaluator`,
and a module-level resolver accessor that the `Generator` sets at the
start of each run. No changes to `ParamExtractor`, `SchemaMapper`,
`OperationBuilder`, or `DocumentBuilder`.

## Path Conventions

Existing Ruby gem: runtime code in `lib/rails_openapi_generator/`, tests in
`spec/` with the dummy Rails app under `spec/fixtures/dummy/`.

---

## Phase 1: Setup

**Purpose**: Version bump, dummy fixtures, and routes the feature needs

- [X] T001 Bump `VERSION` to `0.12.0` in `lib/rails_openapi_generator/version.rb` — constant resolution changes generated output (Constitution V)
- [X] T002 [P] Add `spec/fixtures/dummy/app/services/auto_photo_vhs/enqueue_furniture_generation_service.rb` defining a module/class with five constants: `MOODS = %w[modern classic minimalist scandinavian industrial].freeze`, `PAGE_RANGE = 1..100`, `EMAIL_PATTERN = /\A[^@\s]+@[^@\s]+\z/`, `CLASS_REF = String` (non-schema-compatible), and a no-op `.execute` method so the file is meaningful Ruby
- [X] T003 [P] Add `spec/fixtures/dummy/app/controllers/api/constant_references_controller.rb` exposing: (a) a POST `execute` action with both a top-level `param! :mood, String, in: AutoPhotoVhs::EnqueueFurnitureGenerationService::MOODS` AND a nested `param! :moods, Array, default: [] do |p, i|; p.param! i, String, required: true, in: AutoPhotoVhs::EnqueueFurnitureGenerationService::MOODS; end`; (b) a GET `range` action with `param! :page, Integer, in: AutoPhotoVhs::EnqueueFurnitureGenerationService::PAGE_RANGE`; (c) a GET `pattern` action with `param! :email, String, format: AutoPhotoVhs::EnqueueFurnitureGenerationService::EMAIL_PATTERN`; (d) a GET `non_compatible` action with `param! :x, String, in: AutoPhotoVhs::EnqueueFurnitureGenerationService::CLASS_REF`; (e) a GET `missing` action with `param! :x, String, in: NotAConstantAtAll`
- [X] T004 Add routes for the new actions in `spec/fixtures/dummy/config/routes.rb`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Implement the resolver and the three new evaluator cases so the const-resolution pipeline is in place.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Tests for the foundation ⚠️ (write first, must fail)

- [X] T005 [P] [Test] Add `spec/unit/constant_resolver_spec.rb` covering: schema-compatible Array of Strings → returns the Array; Range of Integers → returns the Range; Regexp → returns the Regexp; primitive (String, Integer, Float, Symbol, true/false) → returns the value; Hash with String/Symbol keys and recursively-compatible values → returns the Hash; Array containing a non-compatible element (e.g. a class) → UNRESOLVED; class constant → UNRESOLVED; NameError on lookup → UNRESOLVED (no exception); LoadError on lookup → UNRESOLVED; the same qualified name resolved twice → only one `Object.const_get` call (caching, asserted via a stub)
- [X] T006 [P] [Test] Extend `spec/unit/literal_evaluator_spec.rb` for the three new node cases: a `:var_ref` carrying `:@const` (e.g. `MOODS`) → calls the resolver; a `:const_path_ref` (`A::B::C`) → builds the joined qualified name and calls the resolver; a `:top_const_ref` (`::FOO`) → calls the resolver with the bare name; a `:var_ref` carrying `:@ident` (a local variable, e.g. `current_user`) → UNRESOLVED (existing path, regression case); with `LiteralEvaluator.resolver` unset (nil) → every constant node case returns UNRESOLVED (default behavior preserved)

### Implementation for the foundation

- [X] T007 Add `lib/rails_openapi_generator/constant_resolver.rb` exposing `ConstantResolver.new` and `#resolve(qualified_name)`: maintain a per-instance `@cache`; on a cache miss, call `Object.const_get(qualified_name, true)` inside `begin ... rescue StandardError, LoadError ... end`; on the resolved value, run `schema_compatible?(value)` (recursive predicate covering primitives, Array of recursively-compatible elements, Hash with String/Symbol keys whose values are recursively compatible, Range of Integers/Floats, Regexp); store the result (or `LiteralEvaluator::UNRESOLVED`) in the cache; return it
- [X] T008 Add a module-level accessor `LiteralEvaluator.resolver` / `resolver=` in `lib/rails_openapi_generator/literal_evaluator.rb` (default `nil`); the resolver is the single shared `ConstantResolver` for the current generator run
- [X] T009 Extend `LiteralEvaluator.evaluate` in `lib/rails_openapi_generator/literal_evaluator.rb` with three new node cases: (a) `:var_ref` whose child is `[:@const, NAME, ...]` → if `resolver` is non-nil, return `resolver.resolve(NAME)`; else UNRESOLVED; (b) `:const_path_ref` → recursively build the qualified name by walking the chain (the left child is itself `:var_ref` / `:const_path_ref` / `:top_const_ref`; the right child is `[:@const, NAME, ...]`), then resolve; (c) `:top_const_ref` → resolve the bare name with no leading namespace. Existing `:var_ref` handling for keyword tokens (`true`/`false`/`nil`) and local-variable idents is preserved by case-discriminating on `node[1][0]`
- [X] T010 Require the new file in `lib/rails_openapi_generator.rb`: add `require_relative "rails_openapi_generator/constant_resolver"` next to the other requires (alphabetically by file name so the diff is minimal)
- [X] T011 Wire the resolver into `Generator#setup_pipeline` in `lib/rails_openapi_generator/generator.rb`: set `LiteralEvaluator.resolver = ConstantResolver.new` at the start of `setup_pipeline`. Resetting on every `build_document` run is sufficient (the cache lifetime matches the generator run)

**Checkpoint**: All foundational specs pass; an action with no constant references emits byte-identical output (sanity-check by running the full existing suite)

---

## Phase 3: User Story 1 - Document a `param!` `in:` enum drawn from a constant (Priority: P1) 🎯 MVP

**Goal**: A `param! :mood, String, in: Module::CONSTANT` where the constant is a literal Array of Strings is documented with `enum: [<MOODS values>]`. The "non-literal param! arguments for mood" warning is no longer emitted for that parameter.

**Independent Test**: Generate against the dummy app and confirm the `execute` operation's `mood` parameter schema has `enum: [<the constant values>]`, and no warning is emitted for the route.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T012 [P] [US1] Add `spec/integration/constant_references_spec.rb` asserting: the `execute` operation's `mood` request-body property has `type: string` and `enum: ["modern", "classic", "minimalist", "scandinavian", "industrial"]`; `GenerationReport.warnings` does NOT contain `"non-literal param! arguments for mood"` for `/api/constant_references/execute`
- [X] T013 [P] [US1] Extend `spec/integration/constant_references_spec.rb` for the `range` and `pattern` operations: `page` has `minimum: 1, maximum: 100`; `email` has `pattern` equal to the regex source (without the `/` delimiters); both routes emit no `"non-literal param!"` warning

### Implementation for User Story 1

No new implementation — T007–T011 (resolver + evaluator + wiring) already deliver this story. T012–T013 verify it end-to-end through the existing `param!` / `SchemaMapper` pipeline (unchanged from `0.11.0`).

**Checkpoint**: MVP — the user's reported `param! :mood, ..., in: Module::CONSTANT` shape documents the constant's actual values; the warning is gone

---

## Phase 4: User Story 2 - Constants used in nested `param!` blocks (Priority: P2)

**Goal**: A nested `p.param! i, String, in: Module::CONSTANT` inside a `param! :moods, Array do |p, i| ... end` block (feature 008) documents the same `enum` on its `items` schema.

**Independent Test**: Generate against the dummy app and confirm the `execute` operation's `moods` request-body property has `type: array` and `items: { type: "string", enum: [<MOODS values>] }`.

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T014 [P] [US2] Extend `spec/integration/constant_references_spec.rb` asserting: the `execute` operation's `moods.items` schema has `type: "string"` and `enum: ["modern", "classic", "minimalist", "scandinavian", "industrial"]`; no warning is emitted for that nested parameter

### Implementation for User Story 2

No new implementation — feature 008's nested-param walker calls the same `LiteralEvaluator.evaluate` for inner option hashes, so the resolver wired in T011 applies inside nested blocks automatically. T014 verifies the recursion is correct.

**Checkpoint**: Nested `param!` blocks pick up resolved constants the same way top-level `param!` calls do

---

## Phase 5: Edge Cases (validation)

**Purpose**: Verify the spec's edge-case rules with focused integration assertions.

- [X] T015 [P] [US1] Extend `spec/integration/constant_references_spec.rb` for the `non_compatible` operation (`in: CLASS_REF` where `CLASS_REF = String`): the parameter is documented (name, type, required), but the schema has NO `enum` key; the existing "non-literal param! arguments for x" warning fires for that route
- [X] T016 [P] [US1] Extend `spec/integration/constant_references_spec.rb` for the `missing` operation (`in: NotAConstantAtAll`): the parameter is documented, no `enum` is emitted, the "non-literal param! arguments" warning fires, AND the generator does not raise; the rest of the document is generated successfully
- [X] T017 [P] [US1] Extend `spec/integration/constant_references_spec.rb` for determinism: two consecutive runs of `execute` produce byte-identical `enum` arrays (order matches the constant's order, which is stable in Ruby)

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Hardening, docs, determinism, regression

- [X] T018 [P] [Test] Extend `spec/integration/feature_001_regression_spec.rb` to assert SC-004: existing `param!`-using endpoints (api/users#index — which uses `param! :query, String, blank: false` and `param! :per_page, Integer, in: 1..100`) emit byte-identical schemas to `0.11.0`; the new resolver does NOT spuriously change literal-array / literal-range schemas
- [X] T019 [P] [Test] Extend `spec/integration/determinism_spec.rb`: the `execute` operation's `mood.enum` and `moods.items.enum` are byte-identical across two runs
- [X] T020 [P] Update `README.md`'s parameter-detection section with a paragraph on constant resolution — bare and qualified constants, the schema-compatible value set (Array of primitives, Range, Regexp, Hash of recursively-compatible values), the silent-on-failure rule, and the per-run cache
- [X] T021 [P] Add a `0.12.0` entry to `CHANGELOG.md` describing constant resolution, the schema-compatible set, the silent-fallback rule, and the SC-004 byte-identical guarantee for endpoints without constant references
- [X] T022 Update the `spec/integration/generate_all_endpoints_spec.rb` route-list assertion to include the new `constant_references` paths
- [X] T023 Run `quickstart.md` end-to-end against the dummy app and correct any discrepancies
- [X] T024 [P] Run RuboCop across the changed `lib/` files and resolve offenses

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately. T003 depends on T002 (the controller references the service constants)
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories. T005/T006 (tests) before T007–T011 (implementation); T007 (resolver class) before T009 (evaluator uses it); T008 (accessor) before T009 (cases read it); T010 (require) before T011 (Generator uses ConstantResolver); T011 wires it all together
- **User Stories (Phase 3–5)**: All depend on Foundational completion
- **Polish (Phase 6)**: Depends on all targeted user stories

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — the MVP, no new implementation (T012–T013 are verification only)
- **US2 (P2)**: Depends on US1 — no new implementation; feature 008's nested walker already invokes `LiteralEvaluator.evaluate`, which now resolves constants via the wired resolver. T014 verifies the nested case end-to-end

### Within Each Phase

- Tests written first and failing before implementation (Constitution III)
- T007 (resolver) before T008 (accessor) and T009 (evaluator cases) — both depend on the resolver class existing
- T010 (require) before T011 (Generator's `setup_pipeline` references `ConstantResolver`)

### Parallel Opportunities

- Setup: T002 and T003 parallel (different files), T004 sequential after T003 (routes reference the controller)
- Foundational tests: T005 and T006 parallel before T007–T011
- US1: T012 and T013 parallel (different assertions in the same new integration file)
- Edge cases: T015, T016, T017 parallel
- Polish: T018, T019, T020, T021, T024 parallel; T022, T023 sequential at the end

---

## Parallel Example: Foundational tests (Phase 2)

```bash
Task: "Add spec/unit/constant_resolver_spec.rb covering the schema-compatibility filter and error rescue"
Task: "Extend spec/unit/literal_evaluator_spec.rb for the three new constant-reference node cases"
```

Both must FAIL before T007–T011 are started.

## Parallel Example: User Story 1 integration

```bash
Task: "execute operation documents mood enum from Service::MOODS"
Task: "range / pattern operations document minimum/maximum / pattern from the resolved constants"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (version bump, service constants, controller, routes)
2. Complete Phase 2: Foundational (resolver + evaluator + Generator wiring)
3. Complete Phase 3: User Story 1 (verification — assert mood/range/pattern operations)
4. **STOP and VALIDATE**: `mood` documents the resolved constant's enum; the warning is gone
5. Demo the MVP — covers the user's reported case

### Incremental Delivery

1. Setup + Foundational → constant resolution available throughout the evaluator
2. US1 → enum/range/pattern from constants documented (MVP)
3. US2 → nested `param!` blocks pick up the same resolution
4. Edge cases → unresolvable / non-schema-compatible / determinism verified
5. Polish → SC-004 regression, README, CHANGELOG, RuboCop

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T007–T011 are tightly coupled)
2. Once Foundational is done:
   - Developer A: US1 + Polish T018 (regression)
   - Developer B: US2 + Edge cases T015–T017
   - Developer C: README + CHANGELOG + RuboCop
3. Polish converges last

---

## Notes

- [P] = different files, no dependency on an incomplete task
- [US#] maps a task to its user story; [Test] marks a non-story test task
- All test specs MUST fail before their implementation task is started
- This feature is purely additive at the per-operation level for any
  endpoint whose `param!` calls have always been fully literal — those
  endpoints MUST produce byte-identical output to `0.11.0` (SC-004, T018)
- Constant references outside `param!` (in `render`, `redirect_to`,
  `respond_to do |format|`, etc.) are out of scope (FR-009); do not add
  them here. A future feature can lift that scope
- Commit after each task or logical group
