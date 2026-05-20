---
description: "Task list for Nested Parameter Blocks"
---

# Tasks: Nested Parameter Blocks

**Input**: Design documents from `/specs/008-nested-param-blocks/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Tests**: Test tasks ARE included — Constitution Principle III (Test-First
Discipline) mandates every behavior change be covered by an automated test
written before/alongside implementation.

**Organization**: Tasks are grouped by user story (US1 P1, US2 P2, US3 P3).
This feature extends the existing gem (features 001–013). The scope is
narrow: add a `nested` field to `ParamCall`, detect `:method_add_block` form
of `param!` in `ParamExtractor`, walk the block body for `<blockvar>.param!`
calls, and recursively build a schema tree consumed by `OperationBuilder`.

## Path Conventions

Existing Ruby gem: runtime code in `lib/rails_openapi_generator/`, tests in
`spec/` with the dummy Rails app under `spec/fixtures/dummy/`.

---

## Phase 1: Setup

**Purpose**: Version bump, dummy fixtures, and routes the feature needs

- [X] T001 Bump `VERSION` to `0.13.0` in `lib/rails_openapi_generator/version.rb` — nested-param-block detection changes generated output (Constitution V)
- [X] T002 [P] Add `spec/fixtures/dummy/app/controllers/api/nested_params_controller.rb` exposing: (a) a POST `search` action with `param! :q, Hash do |q|; q.param! :keyword, String; q.param! :page, Integer, in: 1..100; end` (US1); (b) a POST `tags` action with `param! :tags, Array do |a, i|; a.param! i, String; end` (US2); (c) a POST `moods` action with `param! :moods, Array do |p, i|; p.param! i, String, in: AutoPhotoVhs::EnqueueFurnitureGenerationService::MOODS; end` (US2 + feature 013 integration — the user's reported case); (d) a POST `nested` action with `param! :wrapper, Hash do |w|; w.param! :inner, Hash do |i|; i.param! :leaf, Integer; end; end` (US3 — deep); (e) a POST `empty_block` action with `param! :h, Hash do |q|; end` (FR-007 — empty block, bare object); (f) a POST `non_hash_block` action with `param! :name, String do |s|; s.param! :ignored, Integer; end` (FR-008 — block on non-Hash/Array, ignored)
- [X] T003 Add routes for the new actions in `spec/fixtures/dummy/config/routes.rb`
- [X] T004 Update the `spec/integration/generate_all_endpoints_spec.rb` route-list assertion to include the new `nested_params` paths

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Extend `ParamCall`, detect the `:method_add_block` form of `param!`, walk the block body for `<blockvar>.param!` calls, and surface the nested tree to `OperationBuilder`.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete

### Tests for the foundation ⚠️ (write first, must fail)

- [X] T005 [P] [Test] Extend `spec/unit/param_extractor_spec.rb` for nested-block detection: (a) `param! :q, Hash do |q|; q.param! :a, String; end` → ParamCall with `nested: [ParamCall(name: "a", type: "String")]`; (b) `param! :a, Array do |p, i|; p.param! i, Integer; end` → ParamCall with `nested: ParamCall(name: nil, type: "Integer")`; (c) `param! :h, Hash do |q|; end` (empty block) → ParamCall with `nested: []` (or `nil` — pick the convention); (d) `param! :s, String do |s|; s.param! :x, Integer; end` (block on non-Hash/Array) → ParamCall with `nested: nil` (block ignored, FR-008); (e) nested `param!` whose receiver is NOT the block-var (`params.param! :x, ...`) → not collected as a nested property (FR-006); (f) a `Hash` block whose nested `param!` is itself a `Hash` with its own block (depth 2) → recursive `nested` tree; (g) the outer block param-name is captured (so `do |fmt|; fmt.param! ...; end` works too — receiver matches "fmt", not hard-coded "q")
- [X] T006 [P] [Test] Extend `spec/unit/param_extractor_spec.rb` for the depth bound: when nested depth exceeds `Configuration#method_resolution_depth`, the over-depth subtree's ParamCall has `nested: nil` (bare object/array) and the run still completes (FR-005)
- [X] T007 [P] [Test] Extend `spec/unit/operation_builder_spec.rb` for the new `properties:` / `items:` emission: a top-level ParamCall with `nested: [child]` produces a request-body property whose schema is `{"type": "object", "properties": {...}}` with the child documented; a top-level ParamCall whose type is `Array` and `nested: items_call` produces a property whose schema is `{"type": "array", "items": <child schema>}`; nested properties are sorted alphabetically (matching the existing flat-property sort)

### Implementation for the foundation

- [X] T008 Add `nested` (Array<ParamCall> / ParamCall / nil, default nil) to the `ParamCall` struct in `lib/rails_openapi_generator/param_extractor.rb`. Keep existing fields and helpers unchanged. The default nil preserves SC-005 byte-identity for flat `param!` calls
- [X] T009 Extend `ParamExtractor#param_bang_args` in `lib/rails_openapi_generator/param_extractor.rb` to ALSO match the `:method_add_block` AST shape — the inner call is the existing `:command` / `:method_add_arg` form of `param!`. Return BOTH the args list AND the do-block AST node so the caller can decide whether to descend
- [X] T010 Refactor `ParamExtractor#find_param_calls` in `lib/rails_openapi_generator/param_extractor.rb` to thread a `depth` argument (default 0) and skip recursing INTO the body of a `:method_add_block` whose call is `param!` — its body is walked separately by `extract_nested_calls`, so the top-level walker must not also visit nested `param!` calls (they'd otherwise appear as flat top-level params). Verified by US1's "Hash with two scalar fields" test: only ONE top-level ParamCall (`:q`) appears, not three
- [X] T011 Add `ParamExtractor#extract_nested_calls(body, block_var_names, depth)` in `lib/rails_openapi_generator/param_extractor.rb` — walks the body for `:command_call` nodes whose receiver is `[:var_ref, [:@ident, NAME, ...]]` matching one of the block-var names AND whose method name is `:@ident "param!"`. Returns the args-list for each match. Skips `:def`/`:defs` subtrees. Captures `block_node` if the call itself is wrapped in `:method_add_block` (for nested-nested declarations)
- [X] T012 Extend `ParamExtractor#build_call` (or add a sibling `build_call_with_block`) in `lib/rails_openapi_generator/param_extractor.rb` to accept `block_node` and `depth` arguments. When the resolved type is `"Hash"` or `"Array"` AND a block is present AND `depth < configuration.method_resolution_depth`: capture the block param names via `[:block_var, [:params, [[:@ident, NAME, ...], ...]], ...]`; call `extract_nested_calls(body, names, depth + 1)`; recursively build a ParamCall for each match (passing `depth + 1`). For Hash, store the list in `nested`; for Array, store the LAST one as the single `items` ParamCall. For non-Hash/Array types OR depth-exceeded OR empty block, leave `nested: nil`
- [X] T013 Wire the configured depth bound into `ParamExtractor` (constructor takes `max_depth:`, default `5` matching `method_resolution_depth`'s default); update the `Generator#setup_pipeline` callsite in `lib/rails_openapi_generator/generator.rb` to pass `max_depth: @configuration.method_resolution_depth`
- [X] T014 Extend `OperationBuilder#build_request_body` in `lib/rails_openapi_generator/operation_builder.rb`: when building each request-body property from a ParamCall, if the call has `nested:` set, recursively build the schema tree (object → `{"type": "object", "properties": {sorted_nested}}`; array → `{"type": "array", "items": <child schema>}`). Nested `properties` are sorted alphabetically. Returns the schema tree as the property's schema in place of the flat one
- [X] T015 Extend `OperationBuilder#build_parameters` in `lib/rails_openapi_generator/operation_builder.rb` for the (rare) case of a structured query parameter: if a query ParamCall has `nested:`, apply the same recursive tree builder. (Most structured params live in the request body — this is for completeness)

**Checkpoint**: All existing tests pass; nested-block detection works on the new fixture's `search` and `tags` actions; the depth bound holds; flat `param!` endpoints emit byte-identical output

---

## Phase 3: User Story 1 - Object parameters expose their nested properties (Priority: P1) 🎯 MVP

**Goal**: A `param! :q, Hash do |q| q.param! :keyword, String; q.param! :page, Integer; end` is documented with `q.properties = {keyword: {type: string}, page: {type: integer}}`. The bare-object output for a no-block Hash is preserved.

**Independent Test**: Generate against the dummy app and confirm the `search` operation documents `q` as an object with both nested properties carrying their mapped types and constraints.

### Tests for User Story 1 ⚠️ (write first, must fail)

- [X] T016 [P] [US1] Add `spec/integration/nested_param_blocks_spec.rb` asserting: the `search` operation's request body has a `q` property whose schema is `{"type": "object", "properties": {"keyword": {"type": "string"}, "page": {"type": "integer", "minimum": 1, "maximum": 100}}}`; properties are sorted alphabetically; no warnings are emitted for the route
- [X] T017 [P] [US1] Extend `spec/integration/nested_param_blocks_spec.rb` asserting: the `empty_block` action's `h` property schema is `{"type": "object"}` with NO `properties:` key (FR-007 — bare object fallback)

### Implementation for User Story 1

No new implementation — T008–T015 (foundation) already delivers this story. T016–T017 verify it end-to-end.

**Checkpoint**: MVP — Hash with nested scalar fields is documented; bare-object fallback preserved

---

## Phase 4: User Story 2 - Array parameters describe their item shape (Priority: P2)

**Goal**: A `param! :tags, Array do |a, i| a.param! i, String; end` is documented with `tags.items = {type: string}`. Combined with feature 013, an Array whose nested `in:` references a constant emits the resolved enum in `items.enum`.

**Independent Test**: Generate against the dummy app and confirm the `tags` and `moods` operations document their array `items` schemas with the correct type (and, for `moods`, the resolved enum from the constant).

### Tests for User Story 2 ⚠️ (write first, must fail)

- [X] T018 [P] [US2] Extend `spec/integration/nested_param_blocks_spec.rb` asserting: the `tags` operation's `tags` property schema is `{"type": "array", "items": {"type": "string"}}`
- [X] T019 [P] [US2] Extend `spec/integration/nested_param_blocks_spec.rb` asserting the user's reported case: the `moods` operation's `moods` property schema is `{"type": "array", "items": {"type": "string", "enum": ["modern", "classic", "minimalist", "scandinavian", "industrial"]}}` — constant resolution from feature 013 carries through to the nested `items.enum`

### Implementation for User Story 2

No new implementation — the foundation handles Array nesting the same way as Hash nesting (just with a single `items` ParamCall instead of a list of properties). The constant resolution for `in:` arguments inside the nested block goes through the existing `LiteralEvaluator` path (which has the resolver set by feature 013's wiring). T018–T019 verify end-to-end.

**Checkpoint**: Array with item shape documented; constant-derived enum on nested items works

---

## Phase 5: User Story 3 - Deep nesting is followed and bounded (Priority: P3)

**Goal**: A three-level nested `Hash` declaration is fully described at every level; a declaration beyond the depth bound truncates without error.

**Independent Test**: Generate against the dummy app and confirm the `nested` operation describes all three levels; with `method_resolution_depth` reduced, the deepest level falls back to a bare schema.

### Tests for User Story 3 ⚠️ (write first, must fail)

- [X] T020 [P] [US3] Extend `spec/integration/nested_param_blocks_spec.rb` asserting: the `nested` operation's `wrapper` schema is `{"type": "object", "properties": {"inner": {"type": "object", "properties": {"leaf": {"type": "integer"}}}}}` — three nested levels visible
- [X] T021 [P] [US3] Extend `spec/integration/nested_param_blocks_spec.rb` (or a sibling spec) asserting that with `method_resolution_depth` set to 1, the depth-2 and depth-3 subtrees fall back to bare object schemas (no `properties:`); the document remains valid and the generator does not raise (FR-005 / SC-004)

### Implementation for User Story 3

No new implementation — the depth bound enforcement in T012/T013 already delivers this story. T020–T021 verify end-to-end.

**Checkpoint**: Deep nesting works; depth bound is safe

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Hardening, docs, determinism, regression

- [X] T022 [P] [Test] Extend `spec/integration/feature_001_regression_spec.rb` to assert SC-005 / FR-009: existing flat `param!`-using endpoints (api/users#index, api/users#show, etc.) emit byte-identical request-body and parameter schemas to `0.12.0`. No spurious `nested` field appears in any flat operation's properties
- [X] T023 [P] [Test] Extend `spec/integration/determinism_spec.rb`: the `search` operation's nested `q.properties` map is byte-identical across two consecutive runs, with alphabetical key ordering matching the existing flat-property sort
- [X] T024 [P] [Test] Extend `spec/integration/constant_references_spec.rb` to remove the "limitation: items not yet walked" note on the existing `execute` operation's `moods` property — its `items.enum` should now populate from the constant. Verify the assertion that was previously stubbed (`moods_field["items"]["enum"]`) now passes
- [X] T025 [P] Update `README.md`'s parameter-detection section with a paragraph on nested `param!` blocks: the Hash → object-with-properties rule, the Array → array-with-items rule, the depth bound (reuses `method_resolution_depth`), the block-receiver match rule (FR-006), and how it composes with feature 013's constant resolution
- [X] T026 [P] Add a `0.13.0` entry to `CHANGELOG.md` describing nested-`param!`-block detection, the Hash / Array nested schema shapes, the depth bound, and the SC-005 byte-identical guarantee for flat `param!` calls. Note the multiplicative win with feature 013 — nested `in: Module::CONSTANT` now resolves to `enum:` on the items schema
- [X] T027 Run `quickstart.md` end-to-end against the dummy app and correct any discrepancies
- [X] T028 [P] Run RuboCop across the changed `lib/` files and resolve offenses

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately. T003 depends on T002 (routes reference the controller); T004 depends on T003 (route-list assertion needs the routes to exist)
- **Foundational (Phase 2)**: Depends on Setup — BLOCKS all user stories. T005–T007 (tests) before T008–T015 (implementation); T008 (struct field) before T012 (builder writes it); T009 (outer detection) before T010 (walker uses it); T011 (inner walker) before T012 (builder calls it); T012 (recursion) before T013 (wiring); T014/T015 (emission) after T012 since they consume `nested:`
- **User Stories (Phase 3–5)**: All depend on Foundational completion
- **Polish (Phase 6)**: Depends on all targeted user stories

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational — the MVP, no new implementation (T016–T017 are verification only)
- **US2 (P2)**: Depends on US1 — no new implementation; T018–T019 verify Array nesting + the feature-013 constant resolution carry-through
- **US3 (P3)**: Depends on US1 — no new implementation; T020–T021 verify recursive depth + the safety bound

### Within Each Phase

- Tests written first and failing before implementation (Constitution III)
- T008 (struct field) before T011/T012 (which write it)
- T009 (outer detection) before T010 (top-level walker excludes block bodies)
- T010 before T011 (the inner walker is invoked from the top-level visit, after the block has been identified)
- T012 (builder) before T013 (wiring) and T014/T015 (emission)

### Parallel Opportunities

- Setup: T002 parallel with the rest (it's a new file); T003 sequential after T002; T004 sequential after T003
- Foundational tests: T005, T006, T007 parallel before T008–T015
- US1 verification: T016, T017 parallel
- US2 verification: T018, T019 parallel
- US3 verification: T020, T021 parallel
- Polish: T022, T023, T024, T025, T026, T028 parallel; T027 sequential at the end

---

## Parallel Example: Foundational tests (Phase 2)

```bash
Task: "Extend spec/unit/param_extractor_spec.rb for nested-block detection (Hash, Array, empty, non-Hash-block, receiver-match, recursive)"
Task: "Extend spec/unit/param_extractor_spec.rb for the depth bound"
Task: "Extend spec/unit/operation_builder_spec.rb for properties/items emission"
```

All three must FAIL before T008–T015 are started.

## Parallel Example: User Story 2 (the user's reported case)

```bash
Task: "tags operation documents items.type: string"
Task: "moods operation documents items.enum from the resolved constant — the user's full reported pattern"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (version bump, controller, routes)
2. Complete Phase 2: Foundational (struct + extractor + builder + wiring)
3. Complete Phase 3: User Story 1 (verification — `search` action's q.properties)
4. **STOP and VALIDATE**: Hash with nested scalar fields documents correctly; bare-object fallback preserved
5. Demo the MVP

### Incremental Delivery

1. Setup + Foundational → nested detection + tree emission in place
2. US1 → Hash nested-properties documented (MVP)
3. US2 → Array nested-items documented; constant resolution carries through (THE user's reported case)
4. US3 → Deep nesting + depth bound verified
5. Polish → SC-005 regression, determinism, README, CHANGELOG, update feature-013's "known limitation" assertion

### Parallel Team Strategy

With multiple developers:

1. Team completes Setup + Foundational together (T008–T015 are tightly coupled)
2. Once Foundational is done:
   - Developer A: US1 verification + Polish T022 (regression)
   - Developer B: US2 verification (including the moods case)
   - Developer C: US3 verification + Polish T024 (feature-013 limitation lift)
3. Polish converges last

---

## Notes

- [P] = different files, no dependency on an incomplete task
- [US#] maps a task to its user story; [Test] marks a non-story test task
- All test specs MUST fail before their implementation task is started
- This feature is purely additive at the per-operation level for any
  endpoint whose `param!` calls have no block — those endpoints MUST
  produce byte-identical output to `0.12.0` (SC-005 / FR-009, T022)
- The OpenAPI object-level `required:` array (lifting nested
  `required: true` flags to a parent-object `required:` list) is
  out of scope per the spec's Assumptions section; do not add it
  here. A future feature can lift the assumption
- Commit after each task or logical group
